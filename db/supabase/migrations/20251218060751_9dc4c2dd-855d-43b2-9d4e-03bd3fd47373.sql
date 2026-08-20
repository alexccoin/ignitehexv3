-- Fix wallet PIN hashing regression: trigger was re-hashing already-hashed values,
-- causing newly-set PINs to become invalid.
--
-- 1) Standardize hash_pin_secure() to return bcrypt (same as hash_wallet_pin), so all PIN set/reset flows store a directly-verifiable hash.
-- 2) Update enforce_wallet_pin_hashing() trigger function to ONLY hash raw 6-digit plaintext PIN values,
--    and never re-hash existing hashes (bcrypt, sha256, or custom formats).

CREATE OR REPLACE FUNCTION public.hash_pin_secure(pin_text text, user_uuid uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
BEGIN
  -- Standardize on bcrypt hashes for wallet_pin_hash.
  -- (user_uuid kept for signature compatibility; not required for bcrypt hashing)
  RETURN public.hash_wallet_pin(pin_text);
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_wallet_pin_hashing()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
BEGIN
  -- Only hash when the incoming value is a RAW 6-digit PIN (plaintext).
  -- Never re-hash values that already look hashed (bcrypt, sha256 hex, or custom formats).
  IF NEW.wallet_pin_hash IS NOT NULL AND NEW.wallet_pin_hash ~ '^[0-9]{6}$' THEN
    NEW.wallet_pin_hash := public.hash_wallet_pin(NEW.wallet_pin_hash);
  END IF;

  RETURN NEW;
END;
$$;