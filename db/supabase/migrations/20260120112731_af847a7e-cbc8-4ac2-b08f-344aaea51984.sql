-- Reinstate Thorsten Pötke to approved status so he can pay
UPDATE seed_str_applications 
SET status = 'approved',
    updated_at = now()
WHERE email = 'thorsten.poetke@ev-gmbh.de' 
AND status = 'suspended';