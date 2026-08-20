-- Add currency column to arss_transactions for explicit reward currency tracking
ALTER TABLE arss_transactions 
ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'wSTR';

-- Add comment to clarify that ALL staking rewards are in wSTR
COMMENT ON COLUMN arss_transactions.currency IS 'Currency for transaction - ALL staking rewards are in wSTR regardless of staked token type';

-- Mark all existing staking rewards as wSTR currency
UPDATE arss_transactions 
SET currency = 'wSTR'
WHERE source_type IN ('daily_rewards', 'staking_reward', 'enhanced_migration', 'historical_recalculation', 'balance_correction', 'system_fix')
  AND (currency IS NULL OR currency != 'wSTR');

-- Add index for efficient reward queries by currency
CREATE INDEX IF NOT EXISTS idx_arss_transactions_reward_currency 
ON arss_transactions(source_type, currency, user_id) 
WHERE source_type IN ('daily_rewards', 'staking_reward');

-- Add index for transaction history queries
CREATE INDEX IF NOT EXISTS idx_arss_transactions_user_currency 
ON arss_transactions(user_id, currency, created_at DESC);