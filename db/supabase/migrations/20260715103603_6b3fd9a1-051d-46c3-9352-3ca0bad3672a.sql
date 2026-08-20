CREATE OR REPLACE FUNCTION public.log_sensitive_data_access()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec_json jsonb;
  has_enc boolean := false;
BEGIN
  IF TG_OP = 'DELETE' THEN
    rec_json := to_jsonb(OLD);
  ELSE
    rec_json := to_jsonb(NEW);
  END IF;

  IF TG_TABLE_NAME = 'user_profiles' THEN
    has_enc := COALESCE((rec_json->>'recovery_words_encrypted')::boolean, false);
  ELSIF TG_TABLE_NAME = 'iban_accounts' THEN
    has_enc := COALESCE((rec_json->>'is_data_encrypted')::boolean, false);
  ELSIF TG_TABLE_NAME = 'github_integrations' THEN
    has_enc := COALESCE((rec_json->>'is_token_encrypted')::boolean, false);
  END IF;

  INSERT INTO public.security_audit_log (
    user_id, action, resource_type, resource_id, details, ip_address
  ) VALUES (
    auth.uid(),
    TG_OP || '_sensitive_data',
    TG_TABLE_NAME,
    COALESCE((rec_json->>'id'), '')::text,
    jsonb_build_object(
      'operation', TG_OP,
      'table', TG_TABLE_NAME,
      'timestamp', now(),
      'has_encrypted_data', has_enc
    ),
    get_client_ip()
  );

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;