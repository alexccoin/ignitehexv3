-- Move all supernode holders' USD/STR balance to held_balance (pending)
-- This updates fiat_wallets for users who have supernodes
UPDATE fiat_wallets fw
SET 
  held_balance = balance,
  available_balance = 0,
  updated_at = now()
FROM supernodes s
WHERE fw.user_id = s.user_id
AND fw.currency = 'USD';