-- Fix Thomas's BTC deposit address to use the correct unified sale address
UPDATE guardian_wallets 
SET deposit_address = 'bc1qwxzaesvtf8w8acrll3z0tx58yxcedk6347kxgz' 
WHERE user_id = 'fcf333e7-10e7-4d26-818f-31159f325c73' AND asset_symbol = 'BTC';

-- Fix Thomas's ETH deposit address to use the correct unified sale address
UPDATE guardian_wallets 
SET deposit_address = '0x52A6D71e0AE30f0A62C912C9aAF187c951e82794' 
WHERE user_id = 'fcf333e7-10e7-4d26-818f-31159f325c73' AND asset_symbol = 'ETH';