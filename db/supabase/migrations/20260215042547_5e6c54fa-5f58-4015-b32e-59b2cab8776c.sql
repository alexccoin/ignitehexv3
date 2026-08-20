
-- Fix 1: Update 64 credited apps with mismatched payment_status
UPDATE public.seed_str_applications
SET payment_status = 'payment_verified', status = CASE WHEN status = 'approved' THEN 'verified' ELSE status END, updated_at = now()
WHERE credited_amount > 0 AND payment_status = 'awaiting_payment';

-- Fix 2: Remove 73 empty placeholder STR pools
DELETE FROM public.user_staking_pools
WHERE pool_type = 'str' AND balance = 0 AND staked_amount = 0 AND lock_end_date IS NULL;
