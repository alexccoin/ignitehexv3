-- Fix the STR wallet generation function to only use alphanumeric characters
CREATE OR REPLACE FUNCTION public.generate_str_wallet_address()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  wallet_address TEXT;
  random_chars TEXT;
  chars TEXT := 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  char_length INTEGER := length(chars);
BEGIN
  -- Generate 13 random alphanumeric characters
  random_chars := '';
  FOR i IN 1..13 LOOP
    random_chars := random_chars || substr(chars, floor(random() * char_length + 1)::integer, 1);
  END LOOP;
  
  -- Create wallet address with strzk13 prefix
  wallet_address := 'strzk13' || random_chars;
  
  RETURN wallet_address;
END;
$function$;

-- Update existing wallet addresses that contain symbols
UPDATE public.user_profiles 
SET str_wallet_address = generate_str_wallet_address()
WHERE str_wallet_address ~ '[^a-zA-Z0-9]';