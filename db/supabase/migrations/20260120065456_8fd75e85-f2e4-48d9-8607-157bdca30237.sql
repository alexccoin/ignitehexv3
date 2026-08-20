-- Delete the wrong entry (66,666 investment with payment_verified)
DELETE FROM seed_str_applications WHERE id = '01a27236-aab8-401a-910d-c6fd7133e98e';

-- Update the correct entry (400,000,000 investment) to payment_verified
UPDATE seed_str_applications 
SET payment_status = 'payment_verified',
    payment_verified_at = now(),
    updated_at = now()
WHERE id = '07f98aae-acb0-423a-b201-c3686e17ab93';