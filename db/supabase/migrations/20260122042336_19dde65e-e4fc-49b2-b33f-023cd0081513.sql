UPDATE seed_str_applications 
SET payment_status = 'payment_verified',
    updated_at = now()
WHERE email IN ('tvmn22@hotmail.com', 'bg.trecose@gmx.ch', 'froschnundmaulwurfn@gmail.com', 'christiane.g68@web.de')
AND payment_status = 'awaiting_payment';