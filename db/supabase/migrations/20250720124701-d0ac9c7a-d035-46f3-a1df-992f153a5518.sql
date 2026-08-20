-- Insert pre-built wallet pools from CCoinLP interface for testing
-- Using realistic wallet addresses and balances from the original build
INSERT INTO public.wallet_pools (pool_type, wallet_address, balance, user_id) VALUES
-- BTC pools (6 wallets as shown in the interface)
('BTC', 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh', 2.5, (SELECT id FROM auth.users LIMIT 1)),
('BTC', '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa', 1.75, (SELECT id FROM auth.users LIMIT 1)),
('BTC', '3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy', 0.95, (SELECT id FROM auth.users LIMIT 1)),
('BTC', 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4', 3.2, (SELECT id FROM auth.users LIMIT 1)),
('BTC', '1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2', 0.65, (SELECT id FROM auth.users LIMIT 1)),
('BTC', '3Kzh9qAqVWQhEsfQz7zEQL1EuSx5tyNLNS', 1.45, (SELECT id FROM auth.users LIMIT 1)),

-- CCOS pools (multiple wallets)
('CCOS', '0x742d35Cc6634C0532925a3b8D0934e8dd79D7B99', 150.0, (SELECT id FROM auth.users LIMIT 1)),
('CCOS', '0x8ba1f109551bD432803012645Hac136c770cE2ee', 275.5, (SELECT id FROM auth.users LIMIT 1)),
('CCOS', '0x1234567890123456789012345678901234567890', 95.75, (SELECT id FROM auth.users LIMIT 1)),
('CCOS', '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd', 320.25, (SELECT id FROM auth.users LIMIT 1)),

-- STR pools (multiple wallets)
('STR', 'GDQP2KPQGKIHYJGXNUIYOMHARUARCA7DJT5FO2FFOOKY3B2WSQHG4W37', 10000.0, (SELECT id FROM auth.users LIMIT 1)),
('STR', 'GCKFBEIYTKP5RDRXEP35ZRXNBH6CRYOKZ36KOYXYK2K7RQLEH2CCCNHD', 25000.0, (SELECT id FROM auth.users LIMIT 1)),
('STR', 'GAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAWHF', 15500.5, (SELECT id FROM auth.users LIMIT 1)),
('STR', 'GBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB', 8750.25, (SELECT id FROM auth.users LIMIT 1));