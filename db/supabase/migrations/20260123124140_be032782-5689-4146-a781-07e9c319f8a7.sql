-- Update all CCOS enhanced staking pools to have minimum stake of 10
UPDATE enhanced_staking_pools
SET min_stake_amount = 10
WHERE token_type = 'ccos';