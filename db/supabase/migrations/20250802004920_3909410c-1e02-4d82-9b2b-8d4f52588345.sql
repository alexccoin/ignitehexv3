-- Update password for alex@strlabs.io user directly
-- This will set the password to 'Nokia6280@'

UPDATE auth.users 
SET 
    encrypted_password = crypt('Nokia6280@', gen_salt('bf')),
    updated_at = now()
WHERE email = 'alex@strlabs.io';