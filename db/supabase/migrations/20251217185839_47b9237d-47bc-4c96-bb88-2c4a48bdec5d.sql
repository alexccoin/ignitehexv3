-- Add str. prefix to all usernames that don't have it
-- Skip placeholder values like "To be updated"
UPDATE user_profiles
SET str_domain_username = 'str.' || str_domain_username,
    updated_at = now()
WHERE str_domain_username IS NOT NULL 
  AND str_domain_username != ''
  AND str_domain_username NOT LIKE 'To be updated%'
  AND str_domain_username NOT LIKE 'str.%'
  AND str_domain_username NOT LIKE 'STR.%';