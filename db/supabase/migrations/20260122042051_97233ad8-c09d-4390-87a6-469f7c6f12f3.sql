UPDATE private_seed_str_applications 
SET status = 'verified', 
    payment_status = 'payment_verified',
    processed_at = now(),
    updated_at = now()
WHERE payment_status = 'awaiting_payment' OR status = 'awaiting_payment';