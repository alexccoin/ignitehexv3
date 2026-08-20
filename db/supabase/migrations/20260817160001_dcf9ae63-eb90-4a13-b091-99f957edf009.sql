CREATE OR REPLACE FUNCTION public.generate_ccoin_iban(p_country text)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SET search_path = public
AS $$
DECLARE
  cc text := upper(coalesce(p_country, 'BG'));
  seed text := replace(gen_random_uuid()::text, '-', '');
BEGIN
  RETURN public.ccoin_fix_iban(cc || '00' || regexp_replace(md5(seed || clock_timestamp()::text), '\D', '', 'g') || '1234567890123456789');
END;
$$;

CREATE OR REPLACE FUNCTION public.ccoin_bic_for_country(p_country text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE upper(coalesce(p_country,''))
    WHEN 'BG' THEN 'CCOIBGSF'
    WHEN 'CH' THEN 'CCOICHZZ'
    WHEN 'GB' THEN 'CCOIGB2L'
    WHEN 'DE' THEN 'CCOIDEFF'
    WHEN 'US' THEN 'CCOIUS33'
    ELSE NULL END;
$$;

CREATE OR REPLACE FUNCTION public.normalize_ccoin_iban_row()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_fixed text;
  v_bic text;
BEGIN
  IF NEW.iban IS NULL OR NEW.iban = '' OR NEW.iban = '***ENCRYPTED***' THEN
    RETURN NEW;
  END IF;
  IF length(NEW.iban) > 40 OR NEW.iban !~ '^[A-Za-z]{2}' THEN
    RETURN NEW;
  END IF;

  v_fixed := public.ccoin_fix_iban(NEW.iban);
  IF v_fixed IS NOT NULL AND public.iban_is_valid(v_fixed) THEN
    NEW.iban := v_fixed;
  END IF;

  v_bic := public.ccoin_bic_for_country(coalesce(NEW.country_code, substr(NEW.iban, 1, 2)));
  IF v_bic IS NOT NULL THEN
    NEW.bic := v_bic;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS aaa_normalize_ccoin_iban ON public.iban_accounts;
CREATE TRIGGER aaa_normalize_ccoin_iban
BEFORE INSERT OR UPDATE OF iban, bic, country_code ON public.iban_accounts
FOR EACH ROW EXECUTE FUNCTION public.normalize_ccoin_iban_row();

DROP TRIGGER IF EXISTS aaa_normalize_ccoin_iban ON public.user_plain_ibans;
CREATE TRIGGER aaa_normalize_ccoin_iban
BEFORE INSERT OR UPDATE OF iban, bic, country_code ON public.user_plain_ibans
FOR EACH ROW EXECUTE FUNCTION public.normalize_ccoin_iban_row();

CREATE OR REPLACE FUNCTION public.create_ccoin_iban_for_user(p_user_id uuid, p_full_name text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_iban_id uuid;
BEGIN
  SELECT id INTO v_iban_id FROM iban_accounts WHERE user_id = p_user_id LIMIT 1;
  IF v_iban_id IS NOT NULL THEN
    RETURN v_iban_id;
  END IF;

  INSERT INTO iban_accounts (
    user_id, iban, bic, account_holder, account_type,
    country_code, currency, balance, status, is_data_encrypted
  ) VALUES (
    p_user_id,
    public.generate_ccoin_iban('BG'),
    public.ccoin_bic_for_country('BG'),
    p_full_name, 'personal', 'BG', 'EUR', 0, 'active', false
  )
  RETURNING id INTO v_iban_id;

  RETURN v_iban_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_iban_for_user(
  p_user_id uuid,
  p_currency text,
  p_country text DEFAULT 'CH'::text,
  p_bic text DEFAULT 'CCFINCHZ'::text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing uuid;
  v_id uuid;
  v_country text := upper(coalesce(p_country, 'BG'));
BEGIN
  SELECT id INTO v_existing
  FROM public.iban_accounts
  WHERE user_id = p_user_id AND currency = p_currency
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  INSERT INTO public.iban_accounts (
    user_id, iban, bic, country_code, currency, balance, status,
    is_data_encrypted, created_at, updated_at
  ) VALUES (
    p_user_id,
    public.generate_ccoin_iban(v_country),
    COALESCE(public.ccoin_bic_for_country(v_country), p_bic),
    v_country, p_currency, 0, 'active', false, now(), now()
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;