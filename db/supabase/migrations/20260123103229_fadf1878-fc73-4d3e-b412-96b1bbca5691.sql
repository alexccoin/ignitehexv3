-- Fix: Set payment_status back to 'awaiting_payment' for users who have NOT been credited
-- Only users with credited_amount > 0 AND str_shares_credited > 0 should have 'payment_verified'
UPDATE seed_str_applications 
SET payment_status = 'awaiting_payment',
    updated_at = now()
WHERE (credited_amount = 0 OR credited_amount IS NULL OR str_shares_credited = 0 OR str_shares_credited IS NULL)
AND payment_status = 'payment_verified';