-- Generate STR wallet addresses for existing users who don't have one
UPDATE public.user_profiles 
SET str_wallet_address = generate_str_wallet_address()
WHERE str_wallet_address IS NULL;