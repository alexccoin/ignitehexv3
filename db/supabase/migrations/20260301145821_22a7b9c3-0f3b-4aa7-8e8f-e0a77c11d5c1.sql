-- Accept Joerg's guardian invitation
UPDATE guardian_invitations 
SET status = 'accepted', 
    accepted_by = 'c49a3109-8624-4f60-a280-ba0de1a6245d', 
    accepted_at = now() 
WHERE id = 'b43a9d8b-ba20-4f21-ae41-b6e208aa2a71';

-- Create default wallets for Joerg with correct sale deposit addresses
INSERT INTO guardian_wallets (user_id, asset_symbol, asset_name, network, icon_color, deposit_address, balance, external_balance, usd_value, is_active)
VALUES
  ('c49a3109-8624-4f60-a280-ba0de1a6245d', 'BTC', 'Bitcoin', 'Bitcoin', '#F7931A', 'bc1qwxzaesvtf8w8acrll3z0tx58yxcedk6347kxgz', 0, 0, 0, true),
  ('c49a3109-8624-4f60-a280-ba0de1a6245d', 'ETH', 'Ethereum', 'Ethereum', '#627EEA', '0x52A6D71e0AE30f0A62C912C9aAF187c951e82794', 0, 0, 0, true),
  ('c49a3109-8624-4f60-a280-ba0de1a6245d', 'USDT', 'Tether', 'Polygon', '#26A17B', NULL, 0, 0, 0, true),
  ('c49a3109-8624-4f60-a280-ba0de1a6245d', 'USDC', 'USD Coin', 'Polygon', '#2775CA', NULL, 0, 0, 0, true),
  ('c49a3109-8624-4f60-a280-ba0de1a6245d', 'STR', 'SourceLess', 'SourceLess', '#8B5CF6', NULL, 0, 0, 0, true);