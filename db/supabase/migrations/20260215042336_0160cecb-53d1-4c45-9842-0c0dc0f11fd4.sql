UPDATE public.seed_str_applications
SET payment_deadline = now() + interval '2 days', updated_at = now()
WHERE status = 'approved'
AND payment_status = 'awaiting_payment'
AND payment_deadline < now();