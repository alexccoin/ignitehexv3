-- Update Thorsten Pötke's payment status to payment_verified
UPDATE seed_str_applications 
SET payment_status = 'payment_verified',
    updated_at = now()
WHERE email = 'thorsten.poetke@ev-gmbh.de' 
AND status = 'approved';