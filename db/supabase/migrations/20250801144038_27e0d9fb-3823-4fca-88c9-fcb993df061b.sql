-- Add status column to user_profiles table
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS status text DEFAULT 'pending';

-- Update existing records to have pending status
UPDATE user_profiles SET status = 'pending' WHERE status IS NULL;

-- Create the update user status function
CREATE OR REPLACE FUNCTION update_user_status(target_user_id uuid, new_status text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Update the user status
  UPDATE user_profiles 
  SET status = new_status, updated_at = now()
  WHERE user_id = target_user_id;
  
  -- Return true if update was successful
  RETURN FOUND;
END;
$$;

-- Create admin check function
CREATE OR REPLACE FUNCTION is_admin(check_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = check_user_id
      AND role = 'admin'
  )
$$;

-- Add RLS policies for admin access to user_profiles
CREATE POLICY "Admins can view all user profiles" 
ON public.user_profiles 
FOR SELECT 
USING (is_admin(auth.uid()));

CREATE POLICY "Admins can update all user profiles" 
ON public.user_profiles 
FOR UPDATE 
USING (is_admin(auth.uid()));

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_user_profiles_status ON user_profiles(status);
CREATE INDEX IF NOT EXISTS idx_user_profiles_user_id ON user_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_user_id_role ON user_roles(user_id, role);