-- Fix ALL guardian BTC wallets to use the unified sale address
UPDATE guardian_wallets 
SET deposit_address = 'bc1qwxzaesvtf8w8acrll3z0tx58yxcedk6347kxgz' 
WHERE asset_symbol = 'BTC' AND deposit_address != 'bc1qwxzaesvtf8w8acrll3z0tx58yxcedk6347kxgz';

-- Fix ALL guardian ETH wallets to use the unified sale address
UPDATE guardian_wallets 
SET deposit_address = '0x52A6D71e0AE30f0A62C912C9aAF187c951e82794' 
WHERE asset_symbol = 'ETH' AND deposit_address != '0x52A6D71e0AE30f0A62C912C9aAF187c951e82794';

-- Ensure no other assets have deposit addresses (only BTC/ETH should)
UPDATE guardian_wallets 
SET deposit_address = NULL 
WHERE asset_symbol NOT IN ('BTC', 'ETH') AND deposit_address IS NOT NULL;