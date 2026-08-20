-- Fix user profiles RLS policies to allow users to update their own profiles
-- Drop conflicting restrictive policies that block user updates
DROP POLICY IF EXISTS "Strict admin update user profiles" ON user_profiles;
DROP POLICY IF EXISTS "Strict admin view user profiles" ON user_profiles;

-- Create proper RLS policies for user profiles
CREATE POLICY "Users can view own profile" 
ON user_profiles 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all profiles" 
ON user_profiles 
FOR SELECT 
USING (is_admin(auth.uid()));

CREATE POLICY "Users can update own profile" 
ON user_profiles 
FOR UPDATE 
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can update all profiles" 
ON user_profiles 
FOR UPDATE 
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));