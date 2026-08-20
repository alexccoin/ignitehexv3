UPDATE seed_str_applications 
SET payment_status = 'payment_verified', 
    updated_at = now() 
WHERE email != 'thorsten.poetke@ev-gmbh.de' 
AND status = 'approved';