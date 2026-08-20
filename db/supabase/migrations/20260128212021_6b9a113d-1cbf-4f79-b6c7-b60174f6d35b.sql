-- Extend payment deadline by 72 hours for all Seed STR applications awaiting payment
-- This gives users who haven't paid yet an additional 3 days to complete their payment

UPDATE seed_str_applications 
SET 
  payment_deadline = NOW() + INTERVAL '72 hours',
  updated_at = NOW()
WHERE payment_status IN ('awaiting_payment', 'info_requested')
  AND (payment_hash IS NULL OR payment_hash = '')
  AND status IN ('approved', 'suspended');