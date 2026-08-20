-- Update payment_status to 'payment_verified' for all approved applications that are still showing 'awaiting_payment'
UPDATE seed_str_applications 
SET payment_status = 'payment_verified',
    updated_at = now()
WHERE status = 'approved' 
AND payment_status = 'awaiting_payment';