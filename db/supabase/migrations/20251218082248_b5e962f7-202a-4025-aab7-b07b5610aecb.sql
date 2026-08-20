-- Delete duplicate profiles, keeping the oldest one per email
DELETE FROM user_profiles 
WHERE id IN (
  SELECT id FROM (
    SELECT id, 
           ROW_NUMBER() OVER (PARTITION BY LOWER(email_address) ORDER BY created_at ASC) as rn
    FROM user_profiles
  ) ranked
  WHERE rn > 1
);