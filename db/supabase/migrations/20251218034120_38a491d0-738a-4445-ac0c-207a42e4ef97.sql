-- Normalize str_domain_username across user tables (skip str_domains due to uniqueness constraint)
-- Ensures exactly one str. prefix exists, removes duplicates like str.str. or STR.str.

-- 1. Normalize user_profiles.str_domain_username
UPDATE user_profiles
SET str_domain_username = 
  CASE 
    WHEN str_domain_username IS NULL OR TRIM(str_domain_username) = '' THEN str_domain_username
    WHEN LOWER(TRIM(str_domain_username)) LIKE 'to be%' THEN str_domain_username
    ELSE 'str.' || REGEXP_REPLACE(TRIM(str_domain_username), '^(STR\.|str\.)+', '', 'i')
  END,
  updated_at = now()
WHERE str_domain_username IS NOT NULL 
  AND str_domain_username != ''
  AND (
    str_domain_username ~* '^(STR\.|str\.)(STR\.|str\.)'
    OR str_domain_username ~ '^STR\.'
  );

-- 2. Normalize voucher_redemptions.str_dome_username
UPDATE voucher_redemptions
SET str_dome_username = 
  CASE 
    WHEN str_dome_username IS NULL OR TRIM(str_dome_username) = '' THEN str_dome_username
    WHEN LOWER(TRIM(str_dome_username)) LIKE 'to be%' THEN str_dome_username
    ELSE 'str.' || REGEXP_REPLACE(TRIM(str_dome_username), '^(STR\.|str\.)+', '', 'i')
  END,
  updated_at = now()
WHERE str_dome_username IS NOT NULL 
  AND str_dome_username != ''
  AND (
    str_dome_username ~* '^(STR\.|str\.)(STR\.|str\.)'
    OR str_dome_username ~ '^STR\.'
  );

-- 3. Normalize staking_requests.str_domain_username
UPDATE staking_requests
SET str_domain_username = 
  CASE 
    WHEN str_domain_username IS NULL OR TRIM(str_domain_username) = '' THEN str_domain_username
    WHEN LOWER(TRIM(str_domain_username)) LIKE 'to be%' THEN str_domain_username
    ELSE 'str.' || REGEXP_REPLACE(TRIM(str_domain_username), '^(STR\.|str\.)+', '', 'i')
  END,
  updated_at = now()
WHERE str_domain_username IS NOT NULL 
  AND str_domain_username != ''
  AND (
    str_domain_username ~* '^(STR\.|str\.)(STR\.|str\.)'
    OR str_domain_username ~ '^STR\.'
  );

-- 4. Normalize ccoin_banking_profiles.str_domain (only fix format issues)
UPDATE ccoin_banking_profiles
SET str_domain = 
  CASE 
    WHEN str_domain IS NULL OR TRIM(str_domain) = '' THEN str_domain
    WHEN str_domain ~ '^str\.' THEN str_domain
    WHEN str_domain ~ '^STR\.' THEN 'str.' || SUBSTRING(str_domain FROM 5)
    ELSE str_domain
  END,
  updated_at = now()
WHERE str_domain IS NOT NULL 
  AND str_domain != ''
  AND str_domain ~ '^STR\.';