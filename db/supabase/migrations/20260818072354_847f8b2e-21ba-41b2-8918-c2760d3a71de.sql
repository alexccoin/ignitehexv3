CREATE OR REPLACE FUNCTION public.sync_user_profile_account_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    NEW.account_status := NEW.status::text;
  ELSIF NEW.account_status IS DISTINCT FROM OLD.account_status
        AND NEW.status::text IS DISTINCT FROM NEW.account_status THEN
    BEGIN
      NEW.status := NEW.account_status::account_status;
    EXCEPTION WHEN others THEN
      NEW.account_status := NEW.status::text;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_user_profile_account_status ON public.user_profiles;
CREATE TRIGGER trg_sync_user_profile_account_status
BEFORE UPDATE ON public.user_profiles
FOR EACH ROW EXECUTE FUNCTION public.sync_user_profile_account_status();

CREATE OR REPLACE FUNCTION public.admin_upsert_user_profile_status(target_user_id uuid, new_status text, full_name text DEFAULT NULL::text, email_address text DEFAULT NULL::text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_exists BOOLEAN;
BEGIN
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  SELECT EXISTS(SELECT 1 FROM user_profiles WHERE user_id = target_user_id) INTO v_exists;

  IF v_exists THEN
    UPDATE user_profiles
    SET status = new_status::account_status,
        account_status = new_status,
        updated_at = now()
    WHERE user_id = target_user_id;
  ELSE
    INSERT INTO user_profiles (
      user_id, status, account_status, full_name, email_address, address, city, country,
      postal_code, str_domain_owned, str_domain_username, bsc_wallet_address,
      btc_wallet_address, recovery_words_encrypted, created_at, updated_at
    )
    VALUES (
      target_user_id, new_status::account_status, new_status,
      COALESCE(full_name, 'No Profile Created'),
      COALESCE(email_address, 'unknown@example.com'),
      'To be updated','To be updated','To be updated','To be updated','None',
      'To be updated','To be updated','To be updated', false, now(), now()
    );
  END IF;

  RETURN true;
END;
$function$;

UPDATE public.user_profiles
SET account_status = status::text
WHERE account_status IS DISTINCT FROM status::text;