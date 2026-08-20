-- First delete related audit logs
DELETE FROM private_seed_str_audit_log 
WHERE application_id IN (
  SELECT id FROM private_seed_str_applications 
  WHERE email IN ('golden1960@protonmail.com', 'juergen.poellinger@gmx.de', 'rene@starthaus.de')
);

-- Also delete related access logs
DELETE FROM private_seed_str_access_log 
WHERE application_id IN (
  SELECT id FROM private_seed_str_applications 
  WHERE email IN ('golden1960@protonmail.com', 'juergen.poellinger@gmx.de', 'rene@starthaus.de')
);

-- Now delete the 3 applications
DELETE FROM private_seed_str_applications 
WHERE email IN ('golden1960@protonmail.com', 'juergen.poellinger@gmx.de', 'rene@starthaus.de');