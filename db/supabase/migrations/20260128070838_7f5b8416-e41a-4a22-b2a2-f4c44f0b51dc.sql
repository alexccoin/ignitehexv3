-- Temporarily disable the trigger
ALTER TABLE private_seed_str_applications DISABLE TRIGGER enforce_private_seed_str_application_update;

-- Reset the incorrectly auto-approved applications back to pending
UPDATE private_seed_str_applications 
SET status = 'pending', processed_at = NULL, processed_by = NULL
WHERE email IN ('golden1960@protonmail.com', 'juergen.poellinger@gmx.de', 'rene@starthaus.de')
  AND status = 'approved';

-- Re-enable the trigger
ALTER TABLE private_seed_str_applications ENABLE TRIGGER enforce_private_seed_str_application_update;