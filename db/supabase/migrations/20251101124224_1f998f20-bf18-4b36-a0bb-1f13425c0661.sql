-- Add IP address and country tracking to user_profiles
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS ip_address inet,
ADD COLUMN IF NOT EXISTS country text,
ADD COLUMN IF NOT EXISTS city text,
ADD COLUMN IF NOT EXISTS region text;

-- Create index for country filtering
CREATE INDEX IF NOT EXISTS idx_user_profiles_country ON user_profiles(country);

-- Add comment for documentation
COMMENT ON COLUMN user_profiles.ip_address IS 'User IP address captured during registration';
COMMENT ON COLUMN user_profiles.country IS 'User country derived from IP address (ISO 3166-1 alpha-2 code)';
COMMENT ON COLUMN user_profiles.city IS 'User city derived from IP address';
COMMENT ON COLUMN user_profiles.region IS 'User region/state derived from IP address';