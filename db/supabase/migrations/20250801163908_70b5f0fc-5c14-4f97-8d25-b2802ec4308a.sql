-- Update the current user's CCOIN services to show "not connected/pending" status
UPDATE user_profiles 
SET 
  ccoin_visa_card = 'not connected/pending',
  ccoin_offshore_account_usd = 'not connected/pending',
  updated_at = now()
WHERE user_id = 'bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b';