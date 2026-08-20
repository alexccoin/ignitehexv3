UPDATE seed_str_applications
SET status = 'verified',
    payment_status = 'payment_verified',
    updated_at = now()
WHERE id = 'c81c98a5-9a5b-4c94-baac-e0c88254c0f5';