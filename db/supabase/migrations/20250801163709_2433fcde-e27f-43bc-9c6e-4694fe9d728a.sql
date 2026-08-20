-- Update default values for CCOIN services to show not connected/pending status
ALTER TABLE user_profiles 
ALTER COLUMN ccoin_visa_card SET DEFAULT 'not connected/pending';

ALTER TABLE user_profiles 
ALTER COLUMN ccoin_offshore_account_usd SET DEFAULT 'not connected/pending';

-- Update existing NULL or empty values to show the proper status
UPDATE user_profiles 
SET ccoin_visa_card = 'not connected/pending' 
WHERE ccoin_visa_card IS NULL OR ccoin_visa_card = '';

UPDATE user_profiles 
SET ccoin_offshore_account_usd = 'not connected/pending' 
WHERE ccoin_offshore_account_usd IS NULL OR ccoin_offshore_account_usd = '';