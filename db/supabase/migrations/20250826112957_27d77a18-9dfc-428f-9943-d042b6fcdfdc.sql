-- Clean up duplicate RLS policies on user_profiles
DROP POLICY IF EXISTS "Users can update own profile only" ON user_profiles;
DROP POLICY IF EXISTS "Users can view own profile only" ON user_profiles;

-- Check for any triggers that might block profile updates
SELECT trigger_name, event_manipulation, event_object_table 
FROM information_schema.triggers 
WHERE event_object_table = 'user_profiles';