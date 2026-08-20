-- First delete audit logs for suspended applications
DELETE FROM seed_str_audit_log 
WHERE application_id IN (
  SELECT id FROM seed_str_applications WHERE status = 'suspended'
);

-- Then delete the suspended applications
DELETE FROM seed_str_applications WHERE status = 'suspended';