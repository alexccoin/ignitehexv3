-- Extend payment deadline by 7 days for all expired awaiting_payment applications
UPDATE public.seed_str_applications 
SET payment_deadline = now() + interval '7 days',
    updated_at = now()
WHERE status = 'approved' 
  AND payment_status = 'awaiting_payment' 
  AND payment_deadline < now();