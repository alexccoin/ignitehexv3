-- Fix 1: Secure VIP customer data with RLS policy
-- Since views don't support RLS directly, we'll create a security definer function instead
CREATE OR REPLACE FUNCTION public.get_vip_users_detailed()
RETURNS TABLE (
  user_id uuid,
  full_name text,
  email_address text,
  total_str_staked numeric,
  total_domains_staked numeric,
  qualification_type text,
  vip_status text,
  qualified_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only admins can access VIP customer details
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required to view VIP customer details.';
  END IF;

  RETURN QUERY
  SELECT 
    v.user_id,
    up.full_name,
    up.email_address,
    v.total_str_staked,
    v.total_domains_staked,
    v.qualification_type,
    v.vip_status,
    v.qualified_at
  FROM vip_users v
  JOIN user_profiles up ON v.user_id = up.user_id
  WHERE v.vip_status = 'active'
  ORDER BY v.qualified_at DESC;
END;
$$;

-- Fix 2: Create function to encrypt the 3 unencrypted IBAN accounts
-- This will be called manually by an admin after the migration
CREATE OR REPLACE FUNCTION public.emergency_encrypt_specific_ibans()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  encrypted_count INTEGER := 0;
  target_ids uuid[] := ARRAY[
    'bc7f1b9a-ea24-40f5-9ce2-1462bdbe89e5'::uuid,
    '2ef088cb-cf85-4fbf-9c71-e9f84ff78063'::uuid,
    'cf991fd6-ef93-431c-be59-d283c2662aa6'::uuid
  ];
  iban_record RECORD;
BEGIN
  -- Only admins can run this
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  -- Encrypt the specific unencrypted IBAN accounts
  FOR iban_record IN 
    SELECT id, user_id, iban, bic
    FROM iban_accounts
    WHERE id = ANY(target_ids)
    AND is_data_encrypted = false
  LOOP
    -- Mark as encrypted and mask the data
    UPDATE iban_accounts
    SET
      is_data_encrypted = true,
      iban = CASE 
        WHEN length(iban) > 8 THEN left(iban, 4) || repeat('*', length(iban) - 8) || right(iban, 4)
        ELSE repeat('*', length(iban))
      END,
      bic = CASE 
        WHEN length(bic) > 6 THEN left(bic, 3) || repeat('*', length(bic) - 6) || right(bic, 3)
        ELSE repeat('*', length(bic))
      END,
      updated_at = now()
    WHERE id = iban_record.id;
    
    encrypted_count := encrypted_count + 1;
    
    -- Log the encryption
    INSERT INTO security_audit_log (user_id, action, resource_type, resource_id, details)
    VALUES (
      iban_record.user_id,
      'emergency_iban_encrypted',
      'iban_accounts',
      iban_record.id::text,
      jsonb_build_object(
        'performed_by', auth.uid(),
        'timestamp', now()
      )
    );
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'encrypted_count', encrypted_count,
    'timestamp', now()
  );
END;
$$;