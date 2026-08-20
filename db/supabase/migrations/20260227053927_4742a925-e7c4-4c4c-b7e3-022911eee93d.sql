
-- Accept Thomas Wenz's pending invitation
UPDATE public.guardian_invitations
SET status = 'accepted',
    accepted_by = 'fcf333e7-10e7-4d26-818f-31159f325c73',
    accepted_at = now()
WHERE id = 'f7efbf61-9ddf-444c-b258-5901a9c5cbe9'
  AND status = 'pending';

-- Create default wallets for Thomas Wenz
INSERT INTO public.guardian_wallets (user_id, asset_symbol, asset_name, network, icon_color, deposit_address, balance, external_balance, usd_value, is_active)
VALUES
  ('fcf333e7-10e7-4d26-818f-31159f325c73', 'BTC', 'Bitcoin', 'Bitcoin', '#F7931A', 'bc1qeap7jks0khffccejua4kx4p9m3nvmz0n3tsv2z', 0, 0, 0, true),
  ('fcf333e7-10e7-4d26-818f-31159f325c73', 'ETH', 'Ethereum', 'Ethereum', '#627EEA', '0xBeEE21053b0b7403E6cFa23c70Fe2EF27e632C37', 0, 0, 0, true),
  ('fcf333e7-10e7-4d26-818f-31159f325c73', 'USDT', 'Tether', 'Polygon', '#26A17B', NULL, 0, 0, 0, true),
  ('fcf333e7-10e7-4d26-818f-31159f325c73', 'USDC', 'USD Coin', 'Polygon', '#2775CA', NULL, 0, 0, 0, true),
  ('fcf333e7-10e7-4d26-818f-31159f325c73', 'STR', 'SourceLess', 'SourceLess', '#8B5CF6', NULL, 0, 0, 0, true);
