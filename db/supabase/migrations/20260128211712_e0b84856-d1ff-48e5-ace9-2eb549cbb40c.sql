-- Reset payment deadline for Detlef Mollath's Seed STR application
-- The original 6-hour deadline expired; extending to 72 hours from now

UPDATE seed_str_applications 
SET 
  payment_deadline = NOW() + INTERVAL '72 hours',
  payment_status = 'awaiting_payment',
  updated_at = NOW()
WHERE id = 'd962681b-a33a-4c43-a61c-60b8ae5d15fd'
  AND email = 'detlef1958@me.com';