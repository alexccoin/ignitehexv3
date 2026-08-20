UPDATE seed_str_applications
SET status = 'verified',
    payment_status = 'payment_verified',
    payment_verified_at = now(),
    updated_at = now()
WHERE LOWER(full_name) = 'joerg wittke'
  AND payment_status = 'awaiting_payment';