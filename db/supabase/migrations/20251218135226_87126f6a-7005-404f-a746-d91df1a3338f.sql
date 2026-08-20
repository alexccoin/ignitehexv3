
-- Update Rene Buettner's pools with correct rewards from creation date to today

-- Pool 1: Aug 20 @ 3mo - 120 days @ 12% = 9,863.01 wSTR
UPDATE user_staking_pools 
SET rewards_earned = 9863.01, balance = 250000 + 9863.01
WHERE id = 'da722712-7269-4491-9d23-19afe66a76ad';

-- Pool 2: Aug 20 @ 6mo - 120 days @ 14.75% = 12,123.29 wSTR
UPDATE user_staking_pools 
SET rewards_earned = 12123.29, balance = 250000 + 12123.29
WHERE id = '35d63e3b-7730-4c11-9609-706605d52ec9';

-- Pool 3: Sep 15 @ 12mo - 94 days @ 20% = 69,534.25 wSTR
UPDATE user_staking_pools 
SET rewards_earned = 69534.25, balance = 1350000 + 69534.25
WHERE id = '92f5e422-e9f5-41cc-b768-82e768649d7d';

-- Pool 4: Oct 5 @ 12mo - 74 days @ 20% = 46,630.14 wSTR
UPDATE user_staking_pools 
SET rewards_earned = 46630.14, balance = 1150000 + 46630.14
WHERE id = '4382ae99-1a83-48f3-b4be-cf516e3db1c1';

-- Pool 5: Oct 5 @ 24mo - 74 days @ 31.5% = 73,442.47 wSTR
UPDATE user_staking_pools 
SET rewards_earned = 73442.47, balance = 1150000 + 73442.47
WHERE id = '5363c6cb-2bbc-4f44-bb34-9453f9fa8f44';

-- Pool 6: Oct 7 @ 36mo - 72 days @ 46% = 90,739.73 wSTR
UPDATE user_staking_pools 
SET rewards_earned = 90739.73, balance = 1000000 + 90739.73
WHERE id = '3f7932c4-67f8-4df1-b346-b1f93957b021';

-- Log the backfill rewards in arss_transactions
INSERT INTO arss_transactions (user_id, transaction_type, source_type, amount, currency, status, description)
VALUES 
('cae3131d-c178-4a47-8e93-2eaf9d366f85', 'staking_reward', 'historical_backfill', 9863.01, 'wSTR', 'completed', 
 'Historical backfill: 250k STR @ 3mo (12% APY) - 120 days from Aug 20'),
('cae3131d-c178-4a47-8e93-2eaf9d366f85', 'staking_reward', 'historical_backfill', 12123.29, 'wSTR', 'completed', 
 'Historical backfill: 250k STR @ 6mo (14.75% APY) - 120 days from Aug 20'),
('cae3131d-c178-4a47-8e93-2eaf9d366f85', 'staking_reward', 'historical_backfill', 69534.25, 'wSTR', 'completed', 
 'Historical backfill: 1.35M STR @ 12mo (20% APY) - 94 days from Sep 15'),
('cae3131d-c178-4a47-8e93-2eaf9d366f85', 'staking_reward', 'historical_backfill', 46630.14, 'wSTR', 'completed', 
 'Historical backfill: 1.15M STR @ 12mo (20% APY) - 74 days from Oct 5'),
('cae3131d-c178-4a47-8e93-2eaf9d366f85', 'staking_reward', 'historical_backfill', 73442.47, 'wSTR', 'completed', 
 'Historical backfill: 1.15M STR @ 24mo (31.5% APY) - 74 days from Oct 5'),
('cae3131d-c178-4a47-8e93-2eaf9d366f85', 'staking_reward', 'historical_backfill', 90739.73, 'wSTR', 'completed', 
 'Historical backfill: 1M STR @ 36mo (46% APY) - 72 days from Oct 7');
