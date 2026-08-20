-- Fix #1: Delete empty placeholder STR pools (zero balance, no lock date)
DELETE FROM public.user_staking_pools
WHERE pool_type = 'str'
AND balance = 0
AND staked_amount = 0
AND lock_end_date IS NULL
AND status = 'active';

-- Fix #3: Correct credited applications stuck on "awaiting_payment"
UPDATE public.seed_str_applications
SET payment_status = 'payment_verified',
    status = 'verified',
    updated_at = now()
WHERE credited_amount > 0
AND payment_status = 'awaiting_payment';