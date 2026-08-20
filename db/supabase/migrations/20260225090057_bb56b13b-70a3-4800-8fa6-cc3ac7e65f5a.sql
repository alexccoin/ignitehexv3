
-- Manually accept the invitation and create wallets for alex@strlabs.io
UPDATE guardian_invitations 
SET status = 'accepted', accepted_by = 'bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b', accepted_at = now() 
WHERE id = 'c6833650-32cc-4888-87f1-4d3236e81b4d';

INSERT INTO guardian_wallets (user_id, asset_symbol, asset_name, network, icon_color, deposit_address, balance, external_balance, usd_value, is_active) VALUES
('bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b', 'BTC', 'Bitcoin', 'Bitcoin', '#F7931A', 'bc1qeap7jks0khffccejua4kx4p9m3nvmz0n3tsv2z', 0, 0, 0, true),
('bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b', 'ETH', 'Ethereum', 'Ethereum', '#627EEA', '0xBeEE21053b0b7403E6cFa23c70Fe2EF27e632C37', 0, 0, 0, true),
('bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b', 'USDT', 'Tether', 'Polygon', '#26A17B', NULL, 0, 0, 0, true),
('bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b', 'USDC', 'USD Coin', 'Polygon', '#2775CA', NULL, 0, 0, 0, true),
('bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b', 'STR', 'SourceLess', 'SourceLess', '#8B5CF6', NULL, 0, 0, 0, true);
