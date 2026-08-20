-- Extend payment deadline for Jürgen Peter Aldinger by 7 days from now
UPDATE seed_str_applications
SET payment_deadline = now() + interval '7 days',
    payment_status = 'awaiting_payment'
WHERE id = 'c9546b77-0b2f-404a-a427-057f8ea48998'
  AND user_id = '65f707e1-dbfc-4f10-848a-80a2e91360e2';