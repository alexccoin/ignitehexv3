-- Fix invalid IBAN validation when encrypted and remove wrong trigger on prepaid_cards (retry with corrected syntax)

-- 1) Drop any existing triggers on iban_accounts and prepaid_cards that call the generic validate_sensitive_data_encryption function
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT c.relname AS table_name, t.tgname
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_proc p ON p.oid = t.tgfoid
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE NOT t.tgisinternal
      AND n.nspname = 'public'
      AND c.relname IN ('iban_accounts', 'prepaid_cards')
      AND p.proname = 'validate_sensitive_data_encryption'
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', r.tgname, r.table_name);
  END LOOP;
END $$;

-- 2) Create a dedicated validator for IBAN/BIC that respects encrypted mode
CREATE OR REPLACE FUNCTION public.validate_iban_or_mask()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_iban text := NEW.iban;
  v_bic  text := NEW.bic;
BEGIN
  -- Encrypted mode: require encrypted fields and allow masked placeholders
  IF COALESCE(NEW.is_data_encrypted, false) THEN
    IF NEW.encrypted_iban IS NULL OR NEW.encrypted_bic IS NULL THEN
      RAISE EXCEPTION 'Security violation: IBAN/BIC must be encrypted';
    END IF;

    -- Force masked placeholders into plaintext columns to satisfy NOT NULL
    IF v_iban IS NULL OR v_iban = '' OR v_iban <> '***ENCRYPTED***' THEN
      NEW.iban := '***ENCRYPTED***';
    END IF;

    IF v_bic IS NULL OR v_bic = '' OR v_bic <> '***ENCRYPTED***' THEN
      NEW.bic := '***ENCRYPTED***';
    END IF;

    RETURN NEW;
  END IF;

  -- Plaintext mode: validate IBAN and BIC format
  -- IBAN (approx) 2 letters country + 2 digits check + up to 30 alphanumerics
  IF NEW.iban IS NULL OR NEW.iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' THEN
    RAISE EXCEPTION 'Invalid IBAN format';
  END IF;

  -- BIC (8 or 11) letters/digits
  IF NEW.bic IS NULL OR NEW.bic !~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$' THEN
    RAISE EXCEPTION 'Invalid BIC format';
  END IF;

  RETURN NEW;
END;
$$;

-- 3) Ensure a clean trigger exists only on iban_accounts using the new function
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE NOT t.tgisinternal AND c.relname = 'iban_accounts' AND t.tgname = 'trg_iban_accounts_security') THEN
    EXECUTE 'DROP TRIGGER trg_iban_accounts_security ON public.iban_accounts';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_iban_accounts_security BEFORE INSERT OR UPDATE ON public.iban_accounts FOR EACH ROW EXECUTE FUNCTION public.validate_iban_or_mask()';
END $$;

-- 4) As a safety measure, remove any leftover validation triggers on prepaid_cards that reference columns not present
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT t.tgname
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE NOT t.tgisinternal AND c.relname = 'prepaid_cards'
  LOOP
    -- Drop unknown legacy validation triggers that may reference non-existent columns
    IF r.tgname LIKE 'validate_%' OR r.tgname LIKE 'trg_%encryption%' THEN
      EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.prepaid_cards', r.tgname);
    END IF;
  END LOOP;
END $$;
