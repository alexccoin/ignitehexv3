-- First update the updateUserStatus function to handle actual status updates
CREATE OR REPLACE FUNCTION update_user_status(target_user_id uuid, new_status text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Add status column to user_profiles if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'user_profiles' AND column_name = 'status'
  ) THEN
    ALTER TABLE user_profiles ADD COLUMN status text DEFAULT 'pending';
  END IF;
  
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

-- Allow admin role assignment function to be called by admins
REVOKE ALL ON FUNCTION assign_admin_role FROM PUBLIC;
GRANT EXECUTE ON FUNCTION assign_admin_role TO authenticated;

-- Make sure we have proper indexing for performance
CREATE INDEX IF NOT EXISTS idx_user_profiles_status ON user_profiles(status);
CREATE INDEX IF NOT EXISTS idx_user_profiles_user_id ON user_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_user_id_role ON user_roles(user_id, role);