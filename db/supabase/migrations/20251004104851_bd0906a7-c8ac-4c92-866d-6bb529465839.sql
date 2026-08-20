-- Add airdrop history tracking to user profiles
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS airdrop_applications_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS last_airdrop_application_date TIMESTAMP WITH TIME ZONE;

-- Create function to update user profile on airdrop submission
CREATE OR REPLACE FUNCTION update_user_airdrop_history()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE user_profiles
  SET 
    airdrop_applications_count = COALESCE(airdrop_applications_count, 0) + 1,
    last_airdrop_application_date = NEW.created_at
  WHERE user_id = NEW.user_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Create trigger to automatically update profile when airdrop is submitted
DROP TRIGGER IF EXISTS on_airdrop_registration_created ON airdrop_registrations;
CREATE TRIGGER on_airdrop_registration_created
  AFTER INSERT ON airdrop_registrations
  FOR EACH ROW
  EXECUTE FUNCTION update_user_airdrop_history();

-- Create index for faster queries on user's airdrop history
CREATE INDEX IF NOT EXISTS idx_airdrop_registrations_user_id_created 
ON airdrop_registrations(user_id, created_at DESC);