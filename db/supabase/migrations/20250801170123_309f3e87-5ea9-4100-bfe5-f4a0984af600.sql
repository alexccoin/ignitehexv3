-- Add STR wallet address field to user_profiles table
ALTER TABLE public.user_profiles 
ADD COLUMN str_wallet_address TEXT NULL;

-- Create function to generate STR wallet address
CREATE OR REPLACE FUNCTION public.generate_str_wallet_address()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Create trigger function to auto-generate STR wallet on user creation
CREATE OR REPLACE FUNCTION public.auto_generate_str_wallet()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only generate if str_wallet_address is null
  IF NEW.str_wallet_address IS NULL THEN
    NEW.str_wallet_address := generate_str_wallet_address();
  END IF;
  
  RETURN NEW;
END;
$$;

-- Create trigger to auto-generate STR wallet address on insert
CREATE TRIGGER trigger_auto_generate_str_wallet
  BEFORE INSERT ON public.user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION auto_generate_str_wallet();