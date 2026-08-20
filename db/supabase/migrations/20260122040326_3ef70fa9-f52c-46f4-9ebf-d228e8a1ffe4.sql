UPDATE private_seed_str_applications 
SET status = 'verified', 
    payment_status = 'verified',
    processed_at = now(),
    updated_at = now()
WHERE email IN ('resch.fin@gmail.com', 'christiane.g68@web.de')
AND status = 'awaiting_payment';