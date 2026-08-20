
-- Auto-mint domains for all user profiles with valid unique domain names
-- Exclude placeholders, duplicates, and names that don't meet length requirements (3-63 chars)
WITH clean_domains AS (
  SELECT 
    up.user_id,
    LOWER(REPLACE(REPLACE(up.str_domain_username, 'str.', ''), ' ', '')) as clean_name
  FROM user_profiles up
  WHERE up.str_domain_username IS NOT NULL 
    AND up.str_domain_username != ''
    AND LOWER(up.str_domain_username) NOT IN ('to be updated', 'tobeupdated', 'tbd', 'n/a', 'na', 'none', 'null', 'test')
    AND LOWER(up.str_domain_username) NOT LIKE '%update%'
    AND LENGTH(LOWER(REPLACE(REPLACE(up.str_domain_username, 'str.', ''), ' ', ''))) >= 3
    AND LENGTH(LOWER(REPLACE(REPLACE(up.str_domain_username, 'str.', ''), ' ', ''))) <= 63
    AND NOT EXISTS (
      SELECT 1 FROM str_domains sd 
      WHERE sd.user_id = up.user_id 
      AND sd.status = 'minted'
    )
),
unique_domains AS (
  SELECT clean_name, (array_agg(user_id))[1] as user_id
  FROM clean_domains
  WHERE clean_name NOT IN (SELECT LOWER(domain_name) FROM str_domains)
  GROUP BY clean_name
  HAVING COUNT(*) = 1
)
INSERT INTO str_domains (user_id, domain_name, domain_type, status, minted_at)
SELECT user_id, clean_name, 'personal', 'minted', NOW()
FROM unique_domains;

-- Create a function to auto-mint domain when profile is created/updated with domain username
CREATE OR REPLACE FUNCTION auto_mint_profile_domain()
RETURNS TRIGGER AS $$
DECLARE
  clean_domain_name TEXT;
BEGIN
  -- If str_domain_username is set, ensure a minted domain exists
  IF NEW.str_domain_username IS NOT NULL 
     AND NEW.str_domain_username != '' 
     AND LOWER(NEW.str_domain_username) NOT IN ('to be updated', 'tobeupdated', 'tbd', 'n/a', 'na', 'none', 'null', 'test')
     AND LOWER(NEW.str_domain_username) NOT LIKE '%update%'
  THEN
    clean_domain_name := LOWER(REPLACE(REPLACE(NEW.str_domain_username, 'str.', ''), ' ', ''));
    
    -- Check length requirements (3-63 chars)
    IF LENGTH(clean_domain_name) >= 3 AND LENGTH(clean_domain_name) <= 63 THEN
      -- Only insert if domain doesn't already exist
      IF NOT EXISTS (SELECT 1 FROM str_domains WHERE LOWER(domain_name) = clean_domain_name) THEN
        INSERT INTO str_domains (user_id, domain_name, domain_type, status, minted_at)
        VALUES (NEW.user_id, clean_domain_name, 'personal', 'minted', NOW());
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger to auto-mint on profile insert/update
DROP TRIGGER IF EXISTS trigger_auto_mint_profile_domain ON user_profiles;
CREATE TRIGGER trigger_auto_mint_profile_domain
  AFTER INSERT OR UPDATE OF str_domain_username ON user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION auto_mint_profile_domain();
