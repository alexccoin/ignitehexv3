-- Create admin function to bulk create banking products for all users
CREATE OR REPLACE FUNCTION admin_bulk_create_banking(product_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_record RECORD;
  created_count INTEGER := 0;
  skipped_count INTEGER := 0;
  error_count INTEGER := 0;
  result_id uuid;
BEGIN
  -- Only admins can run this
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  -- Loop through all approved users
  FOR user_record IN
    SELECT 
      up.user_id,
      up.full_name,
      COALESCE(upconn.str_domain, 'user' || substring(up.user_id::text, 1, 8)) as str_domain,
      up.str_wallet_address
    FROM user_profiles up
    LEFT JOIN user_profile_connections upconn ON up.user_id = upconn.user_id
    WHERE up.status = 'approved'
    ORDER BY up.created_at
  LOOP
    BEGIN
      IF product_type = 'iban' THEN
        -- Check if user already has an IBAN
        IF NOT EXISTS (SELECT 1 FROM iban_accounts WHERE user_id = user_record.user_id LIMIT 1) THEN
          result_id := create_ccoin_iban_for_user(user_record.user_id, user_record.full_name);
          IF result_id IS NOT NULL THEN
            created_count := created_count + 1;
          END IF;
        ELSE
          skipped_count := skipped_count + 1;
        END IF;
        
      ELSIF product_type = 'ccoin_card' THEN
        -- Check if user already has a CCoin card
        IF NOT EXISTS (SELECT 1 FROM prepaid_cards WHERE user_id = user_record.user_id AND network = 'ccoin' LIMIT 1) THEN
          result_id := create_ccoin_card_for_user(
            user_record.user_id,
            user_record.str_domain,
            user_record.str_wallet_address
          );
          IF result_id IS NOT NULL THEN
            created_count := created_count + 1;
          END IF;
        ELSE
          skipped_count := skipped_count + 1;
        END IF;
        
      ELSIF product_type = 'visa_card' THEN
        -- Check if user already has a Visa card
        IF NOT EXISTS (SELECT 1 FROM prepaid_cards WHERE user_id = user_record.user_id AND network = 'visa' LIMIT 1) THEN
          result_id := create_visa_card_for_user(
            user_record.user_id,
            user_record.str_domain
          );
          IF result_id IS NOT NULL THEN
            created_count := created_count + 1;
          END IF;
        ELSE
          skipped_count := skipped_count + 1;
        END IF;
      END IF;
      
    EXCEPTION WHEN OTHERS THEN
      error_count := error_count + 1;
      -- Log error but continue processing
      INSERT INTO security_audit_log (user_id, action, resource_type, details)
      VALUES (
        user_record.user_id,
        'bulk_banking_creation_error',
        product_type,
        jsonb_build_object(
          'error', SQLERRM,
          'performed_by', auth.uid(),
          'timestamp', now()
        )
      );
    END;
  END LOOP;

  -- Log the bulk operation
  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (
    auth.uid(),
    'bulk_banking_creation_completed',
    product_type,
    jsonb_build_object(
      'created_count', created_count,
      'skipped_count', skipped_count,
      'error_count', error_count,
      'timestamp', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'product_type', product_type,
    'created', created_count,
    'skipped', skipped_count,
    'errors', error_count,
    'timestamp', now()
  );
  
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'timestamp', now()
  );
END;
$$;