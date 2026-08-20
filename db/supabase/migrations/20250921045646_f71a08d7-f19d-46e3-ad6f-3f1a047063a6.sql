-- Fix Marcus Staudenmeyer's negative balance
-- Current: -1,096,535.86 STR, Expected: 1,098,677.50 STR, Need to add: 2,195,213.36 STR
UPDATE user_staking_pools 
SET balance = 1098677.50191780821918,
    updated_at = now()
WHERE user_id = '98b5323c-78c9-400c-9358-f0336e562fda' AND pool_type = 'str';

-- Log Marcus correction transaction
INSERT INTO arss_transactions (
  user_id, amount, transaction_type, source_type, description, status
) VALUES (
  '98b5323c-78c9-400c-9358-f0336e562fda',
  2195213.36,
  'balance_correction',
  'admin_fix_negative',
  'Balance correction for Marcus Staudenmeyer: Added 2,195,213.36 STR to fix negative balance',
  'completed'
);

-- Fix Thomas Behr's negative balance  
-- Current: -822,205.01 STR, Expected: 824,205.01 STR, Need to add: 1,646,410.02 STR
UPDATE user_staking_pools 
SET balance = 824205.01,
    updated_at = now()
WHERE user_id = 'bb4a2461-ae7e-42e7-b290-2f78731b4c71' AND pool_type = 'str';

-- Log Thomas correction transaction
INSERT INTO arss_transactions (
  user_id, amount, transaction_type, source_type, description, status
) VALUES (
  'bb4a2461-ae7e-42e7-b290-2f78731b4c71',
  1646410.02,
  'balance_correction', 
  'admin_fix_negative',
  'Balance correction for Thomas Behr: Added 1,646,410.02 STR to fix negative balance',
  'completed'
);