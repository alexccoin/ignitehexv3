-- ============================================
-- SECURITY FIX 1: Add admin validation to process_pending_transfer
-- ============================================

CREATE OR REPLACE FUNCTION process_pending_transfer(
  p_tx_id text,
  p_action text, -- 'approve', 'decline', 'pause', or 'refund'
  p_admin_id uuid,
  p_admin_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pending record;
  v_to_user_id uuid;
  v_result jsonb;
BEGIN
  -- ======= SECURITY: Validate admin privileges =======
  -- Check that the calling user matches the admin parameter
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  
  IF auth.uid() != p_admin_id THEN
    RAISE EXCEPTION 'Admin ID mismatch: unauthorized access attempt';
  END IF;
  
  -- Check that the user has admin role
  IF NOT is_admin(p_admin_id) THEN
    RAISE EXCEPTION 'Admin privileges required to process transfers';
  END IF;
  
  -- Log security audit event
  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (
    p_admin_id, 
    'process_pending_transfer', 
    'pending_transfers_treasury',
    jsonb_build_object(
      'tx_id', p_tx_id, 
      'action', p_action,
      'timestamp', now()
    )
  );
  -- ======= END SECURITY VALIDATION =======

  -- Get pending transfer
  SELECT * INTO v_pending
  FROM pending_transfers_treasury
  WHERE tx_id = p_tx_id AND status IN ('held', 'paused')
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pending transfer not found or already processed';
  END IF;

  IF p_action = 'approve' THEN
    -- Find the recipient user by domain
    SELECT user_id INTO v_to_user_id
    FROM user_profiles
    WHERE str_domain_owned ILIKE v_pending.to_identifier
    LIMIT 1;

    IF v_to_user_id IS NULL THEN
      RAISE EXCEPTION 'Recipient domain still does not exist: %', v_pending.to_identifier;
    END IF;

    -- Credit recipient's fiat wallet
    INSERT INTO fiat_wallets (user_id, currency, balance, available_balance)
    VALUES (v_to_user_id, v_pending.currency, v_pending.amount, v_pending.amount)
    ON CONFLICT (user_id, currency)
    DO UPDATE SET
      balance = fiat_wallets.balance + v_pending.amount,
      available_balance = fiat_wallets.available_balance + v_pending.amount,
      updated_at = now();

    -- Create completed transaction record
    INSERT INTO fiat_transactions (
      tx_id,
      from_user_id,
      to_user_id,
      from_identifier,
      to_identifier,
      currency,
      amount,
      fee,
      transfer_type,
      status,
      completed_at,
      metadata
    ) VALUES (
      v_pending.tx_id,
      v_pending.from_user_id,
      v_to_user_id,
      (SELECT str_domain_owned FROM user_profiles WHERE user_id = v_pending.from_user_id),
      v_pending.to_identifier,
      v_pending.currency,
      v_pending.amount,
      v_pending.fee,
      v_pending.transfer_type,
      'completed',
      now(),
      jsonb_build_object(
        'approved_by', p_admin_id,
        'approved_at', now(),
        'was_pending', true
      )
    );

    v_result := jsonb_build_object(
      'action', 'approved',
      'credited_to', v_to_user_id,
      'amount', v_pending.amount,
      'currency', v_pending.currency
    );

  ELSIF p_action = 'decline' THEN
    -- Return funds to sender
    INSERT INTO fiat_wallets (user_id, currency, balance, available_balance)
    VALUES (v_pending.from_user_id, v_pending.currency, v_pending.amount, v_pending.amount)
    ON CONFLICT (user_id, currency)
    DO UPDATE SET
      balance = fiat_wallets.balance + v_pending.amount,
      available_balance = fiat_wallets.available_balance + v_pending.amount,
      updated_at = now();

    -- Create refund transaction record
    INSERT INTO fiat_transactions (
      tx_id,
      from_user_id,
      to_user_id,
      from_identifier,
      to_identifier,
      currency,
      amount,
      fee,
      transfer_type,
      status,
      completed_at,
      metadata
    ) VALUES (
      v_pending.tx_id || '_refund',
      v_pending.from_user_id,
      v_pending.from_user_id,
      'TREASURY',
      (SELECT str_domain_owned FROM user_profiles WHERE user_id = v_pending.from_user_id),
      v_pending.currency,
      v_pending.amount,
      0,
      'refund',
      'completed',
      now(),
      jsonb_build_object(
        'declined_by', p_admin_id,
        'declined_at', now(),
        'reason', p_admin_notes,
        'original_tx', v_pending.tx_id
      )
    );

    v_result := jsonb_build_object(
      'action', 'declined',
      'refunded_to', v_pending.from_user_id,
      'amount', v_pending.amount,
      'currency', v_pending.currency
    );

  ELSIF p_action = 'pause' THEN
    v_result := jsonb_build_object(
      'action', 'paused',
      'tx_id', v_pending.tx_id
    );

  ELSIF p_action = 'refund' THEN
    -- Return funds to sender (same as decline but different action type)
    INSERT INTO fiat_wallets (user_id, currency, balance, available_balance)
    VALUES (v_pending.from_user_id, v_pending.currency, v_pending.amount + COALESCE(v_pending.fee, 0), v_pending.amount + COALESCE(v_pending.fee, 0))
    ON CONFLICT (user_id, currency)
    DO UPDATE SET
      balance = fiat_wallets.balance + v_pending.amount + COALESCE(v_pending.fee, 0),
      available_balance = fiat_wallets.available_balance + v_pending.amount + COALESCE(v_pending.fee, 0),
      updated_at = now();

    v_result := jsonb_build_object(
      'action', 'refunded',
      'refunded_to', v_pending.from_user_id,
      'amount', v_pending.amount + COALESCE(v_pending.fee, 0),
      'currency', v_pending.currency
    );

  ELSE
    RAISE EXCEPTION 'Invalid action: %. Must be approve, decline, pause, or refund', p_action;
  END IF;

  -- Update pending transfer status
  UPDATE pending_transfers_treasury
  SET 
    status = CASE 
      WHEN p_action = 'approve' THEN 'completed'
      WHEN p_action = 'decline' THEN 'declined'
      WHEN p_action = 'pause' THEN 'paused'
      WHEN p_action = 'refund' THEN 'refunded'
    END,
    processed_at = now(),
    processed_by = p_admin_id,
    admin_notes = COALESCE(p_admin_notes, admin_notes)
  WHERE tx_id = p_tx_id;

  RETURN v_result;
END;
$$;

-- ============================================
-- SECURITY FIX 2: Restrict public access to auction bids
-- ============================================

-- Drop the overly permissive public SELECT policy
DROP POLICY IF EXISTS "Anyone can view bids on listings" ON domain_marketplace_bids;

-- Create restrictive policy: users can only see bids they're involved in
CREATE POLICY "Authenticated users view relevant bids"
ON domain_marketplace_bids FOR SELECT
TO authenticated
USING (
  -- Users can see their own bids
  auth.uid() = bidder_id 
  OR
  -- Sellers can see bids on their listings
  listing_id IN (
    SELECT id FROM domain_marketplace_listings 
    WHERE seller_id = auth.uid()
  )
  OR
  -- Admins can see all bids
  is_admin(auth.uid())
);