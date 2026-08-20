-- Clean up @ symbols from usernames (they shouldn't have @)
UPDATE user_profiles
SET str_domain_username = REPLACE(str_domain_username, '@', ''),
    updated_at = now()
WHERE str_domain_username LIKE '%@%'
  AND str_domain_username NOT LIKE '%@%.%'  -- Keep emails intact
  AND str_domain_username LIKE 'str.@%';    -- Only fix str.@ patterns