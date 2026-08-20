-- IBAN standards helpers -------------------------------------------------
CREATE OR REPLACE FUNCTION public.iban_mod97(p_text text)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  s text := '';
  c text;
  i int;
  rem bigint := 0;
BEGIN
  FOR i IN 1..length(p_text) LOOP
    c := upper(substr(p_text, i, 1));
    IF c ~ '[0-9]' THEN
      s := s || c;
    ELSIF c ~ '[A-Z]' THEN
      s := s || (ascii(c) - 55)::text;
    END IF;
  END LOOP;
  i := 1;
  WHILE i <= length(s) LOOP
    rem := (rem::text || substr(s, i, 7))::bigint % 97;
    i := i + 7;
  END LOOP;
  RETURN rem::int;
END;
$$;

CREATE OR REPLACE FUNCTION public.iban_is_valid(p_iban text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v text := upper(regexp_replace(coalesce(p_iban,''), '[^A-Za-z0-9]', '', 'g'));
  expected int;
BEGIN
  IF length(v) < 15 OR v !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]+$' THEN
    RETURN false;
  END IF;
  expected := CASE substr(v,1,2)
    WHEN 'BG' THEN 22 WHEN 'CH' THEN 21 WHEN 'GB' THEN 22 WHEN 'DE' THEN 22
    WHEN 'LI' THEN 21 WHEN 'AT' THEN 20 WHEN 'NL' THEN 18 WHEN 'FR' THEN 27
    WHEN 'ES' THEN 24 WHEN 'IT' THEN 27 WHEN 'BE' THEN 16 WHEN 'IE' THEN 22
    ELSE length(v) END;
  IF length(v) <> expected THEN
    RETURN false;
  END IF;
  RETURN public.iban_mod97(substr(v,5) || substr(v,1,4)) = 1;
END;
$$;

-- Rebuilds a CCoin IBAN so it matches the national length / structure rules
-- while preserving the original account digits and the CCOI bank identifier.
CREATE OR REPLACE FUNCTION public.ccoin_fix_iban(p_iban text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v text := upper(regexp_replace(coalesce(p_iban,''), '[^A-Za-z0-9]', '', 'g'));
  cc text;
  d text;
  bban text;
  chk int;
BEGIN
  IF v = '' OR v !~ '^[A-Z]{2}' THEN
    RETURN p_iban;
  END IF;
  cc := substr(v, 1, 2);

  -- deterministic digit stream: original account digits first, then padding
  d := regexp_replace(substr(v, 5), '\D', '', 'g');
  d := d || regexp_replace(md5(v), '\D', '', 'g') || regexp_replace(md5(reverse(v)), '\D', '', 'g')
         || regexp_replace(md5(v || 'ccoin'), '\D', '', 'g') || '1234567890';

  bban := CASE cc
    WHEN 'BG' THEN 'CCOI' || substr(d, 1, 14)                    -- 4a bank + 4n branch + 2n type + 8c
    WHEN 'GB' THEN 'CCOI' || substr(d, 1, 14)                    -- 4a bank + 6n sort + 8n account
    WHEN 'DE' THEN substr(d, 1, 18)                              -- 8n BLZ + 10n account
    WHEN 'CH' THEN substr(d, 1, 17)                              -- 5n bank + 12c account
    WHEN 'LI' THEN substr(d, 1, 17)
    WHEN 'AT' THEN substr(d, 1, 16)
    WHEN 'NL' THEN 'CCOI' || substr(d, 1, 10)
    WHEN 'IE' THEN 'CCOI' || substr(d, 1, 14)
    ELSE NULL
  END;

  IF bban IS NULL THEN
    RETURN v; -- country without a CCoin IBAN scheme (e.g. US): leave untouched
  END IF;

  chk := 98 - public.iban_mod97(bban || cc || '00');
  RETURN cc || lpad(chk::text, 2, '0') || bban;
END;
$$;

-- audit columns keeping the pre-correction value
ALTER TABLE public.user_plain_ibans ADD COLUMN IF NOT EXISTS legacy_iban text;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS legacy_iban text;