-- Create pending transfers treasury table
CREATE TABLE IF NOT EXISTS pending_transfers_treasury (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tx_id text NOT NULL UNIQUE,
  from_user_id uuid NOT NULL,
  to_identifier text NOT NULL,
  currency text NOT NULL,
  amount numeric NOT NULL,
  fee numeric DEFAULT 0,
  transfer_type text NOT NULL,
  status text NOT NULL DEFAULT 'held',
  held_until timestamp with time zone DEFAULT (now() + interval '30 days'),
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  processed_at timestamp with time zone,
  processed_by uuid,
  admin_notes text
);

-- Enable RLS
ALTER TABLE pending_transfers_treasury ENABLE ROW LEVEL SECURITY;

-- Admins can view all pending transfers
CREATE POLICY "Admins can view all pending transfers"
ON pending_transfers_treasury FOR SELECT
USING (is_admin(auth.uid()));

-- Admins can update pending transfers
CREATE POLICY "Admins can update pending transfers"
ON pending_transfers_treasury FOR UPDATE
USING (is_admin(auth.uid()));

-- System can insert pending transfers
CREATE POLICY "System can insert pending transfers"
ON pending_transfers_treasury FOR INSERT
WITH CHECK (true);

-- Users can view their own pending transfers
CREATE POLICY "Users can view own pending transfers"
ON pending_transfers_treasury FOR SELECT
USING (auth.uid() = from_user_id);

-- Create function to process pending transfer (approve or decline)
CREATE OR REPLACE FUNCTION process_pending_transfer(
  p_tx_id text,
  p_action text, -- 'approve' or 'decline'
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
  -- Get pending transfer
  SELECT * INTO v_pending
  FROM pending_transfers_treasury
  WHERE tx_id = p_tx_id AND status = 'held'
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
      v_pending.tx_id || '_REFUND',
      v_pending.from_user_id,
      v_pending.from_user_id,
      'system',
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
        'original_tx', v_pending.tx_id,
        'reason', p_admin_notes
      )
    );

    v_result := jsonb_build_object(
      'action', 'declined',
      'refunded_to', v_pending.from_user_id,
      'amount', v_pending.amount,
      'currency', v_pending.currency
    );

  ELSE
    RAISE EXCEPTION 'Invalid action. Must be approve or decline';
  END IF;

  -- Update pending transfer status
  UPDATE pending_transfers_treasury
  SET
    status = CASE WHEN p_action = 'approve' THEN 'approved' ELSE 'declined' END,
    processed_at = now(),
    processed_by = p_admin_id,
    admin_notes = p_admin_notes
  WHERE tx_id = p_tx_id;

  RETURN v_result;
END;
$$;