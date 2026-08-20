-- Fix missing function by removing dependency on gen_random_bytes and adding an overload
CREATE OR REPLACE FUNCTION public.create_iban_for_user(p_user_id uuid, p_currency text, p_country text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_iban_id uuid;
  v_masked_iban text;
  v_masked_bic text;
  v_existing uuid;
  v_seed text;
BEGIN
  -- Reuse an existing IBAN for this user if present (idempotent)
  SELECT ia.id
  INTO v_existing
  FROM public.iban_accounts ia
  WHERE ia.user_id = p_user_id
  ORDER BY ia.created_at
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  -- Generate deterministic-length masked placeholders using extensions.digest
  v_seed := encode(extensions.digest(now()::text || random()::text || coalesce(p_currency,'X') || coalesce(p_country,'X'), 'sha256'), 'hex');

  v_masked_iban := 'IBAN' || substr(v_seed, 1, 20);
  IF length(v_masked_iban) > 8 THEN
    v_masked_iban := left(v_masked_iban, 4) || repeat('*', greatest(length(v_masked_iban) - 8, 0)) || right(v_masked_iban, 4);
  ELSE
    v_masked_iban := repeat('*', length(v_masked_iban));
  END IF;

  v_masked_bic := 'BIC' || substr(v_seed, 5, 8);
  IF length(v_masked_bic) > 6 THEN
    v_masked_bic := left(v_masked_bic, 3) || repeat('*', greatest(length(v_masked_bic) - 6, 0)) || right(v_masked_bic, 3);
  ELSE
    v_masked_bic := repeat('*', length(v_masked_bic));
  END IF;

  INSERT INTO public.iban_accounts (user_id, iban, bic, is_data_encrypted)
  VALUES (p_user_id, v_masked_iban, v_masked_bic, true)
  RETURNING id INTO v_iban_id;

  RETURN v_iban_id;
END;
$$;

-- Overload to support 2-arg calls
CREATE OR REPLACE FUNCTION public.create_iban_for_user(p_user_id uuid, p_currency text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.create_iban_for_user(p_user_id, p_currency, NULL::text);
END;
$$;