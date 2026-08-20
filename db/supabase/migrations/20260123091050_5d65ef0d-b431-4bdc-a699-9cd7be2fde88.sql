-- Update all seed_str_applications where user has been credited with BOTH tokens and shares
UPDATE seed_str_applications 
SET payment_status = 'payment_verified',
    updated_at = now()
WHERE payment_status = 'awaiting_payment'
AND credited_amount > 0 
AND str_shares_credited > 0;