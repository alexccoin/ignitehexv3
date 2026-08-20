UPDATE private_seed_str_applications 
SET status = 'verified', 
    payment_status = 'payment_verified',
    processed_at = now(),
    updated_at = now()
WHERE email IN ('froschnundmaulwurfn@gmail.com', 'bg.trecose@gmx.ch', 'tvmn22@hotmail.com')
AND status = 'awaiting_payment';