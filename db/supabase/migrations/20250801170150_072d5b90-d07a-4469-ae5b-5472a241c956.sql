-- Fix security warnings by adding proper search path to functions

-- Update generate_str_wallet_address function with secure search path
CREATE OR REPLACE FUNCTION public.generate_str_wallet_address()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  wallet_address TEXT;
  random_chars TEXT;
BEGIN
  -- Generate 13 random alphanumeric characters
  random_chars := array_to_string(ARRAY(
    SELECT chr((ascii('0') + round(random() * 25)) :: integer)
    FROM generate_series(1, 13)
  ), '');
  
  -- Replace some numbers with letters for better randomness
  random_chars := translate(random_chars, '012345', 'abcdef');
  
  -- Create wallet address with strzk13 prefix
  wallet_address := 'strzk13' || random_chars;
  
  RETURN wallet_address;
END;
$$;

-- Update auto_generate_str_wallet function with secure search path
CREATE OR REPLACE FUNCTION public.auto_generate_str_wallet()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Only generate if str_wallet_address is null
  IF NEW.str_wallet_address IS NULL THEN
    NEW.str_wallet_address := generate_str_wallet_address();
  END IF;
  
  RETURN NEW;
END;
$$;