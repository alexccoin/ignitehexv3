-- Extend payment deadline for ALL expired Seed STR applications by 7 days from now
UPDATE seed_str_applications
SET payment_deadline = now() + interval '7 days'
WHERE payment_deadline < now()
  AND payment_status = 'awaiting_payment'
  AND status = 'approved';