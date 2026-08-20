UPDATE seed_str_applications 
SET status = 'verified', 
    payment_status = 'payment_verified',
    updated_at = now()
WHERE id = '5b74a0d8-8846-485b-86d2-de62cbd5c0af' 
AND full_name = 'Sandra Kerstin Zimmermann';