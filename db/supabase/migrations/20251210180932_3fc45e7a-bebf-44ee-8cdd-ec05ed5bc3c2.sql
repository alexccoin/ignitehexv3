-- Add seller_eth_wallet column for personal listings with USD price
ALTER TABLE domain_marketplace_listings 
ADD COLUMN IF NOT EXISTS seller_eth_wallet TEXT;