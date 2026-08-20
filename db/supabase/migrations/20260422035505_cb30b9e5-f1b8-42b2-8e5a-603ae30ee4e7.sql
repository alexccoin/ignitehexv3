-- Backfill: any application that has tokens or shares credited should be marked as payment verified

UPDATE public.seed_str_applications
SET payment_status = 'payment_verified',
    status = 'verified',
    payment_verified_at = COALESCE(payment_verified_at, credited_at, now()),
    updated_at = now()
WHERE (COALESCE(credited_amount, 0) > 0 OR COALESCE(str_shares_credited, 0) > 0)
  AND payment_status <> 'payment_verified';

UPDATE public.private_seed_str_applications
SET payment_status = 'payment_verified',
    status = 'verified',
    updated_at = now()
WHERE (COALESCE(credited_amount, 0) > 0 OR COALESCE(str_shares_credited, 0) > 0)
  AND payment_status <> 'payment_verified';