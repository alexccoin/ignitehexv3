-- Drop the insecure policy that allows users to update any field including status
DROP POLICY IF EXISTS "Users can update own private seed str applications" ON public.private_seed_str_applications;

-- Create a security definer function to check if update only touches allowed fields
CREATE OR REPLACE FUNCTION public.validate_private_seed_str_application_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Check if user is admin
  IF public.has_role(auth.uid(), 'admin'::app_role) OR public.has_role(auth.uid(), 'seed_str_admin'::app_role) THEN
    -- Admins can update anything
    RETURN NEW;
  END IF;
  
  -- Non-admins cannot change protected fields
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'You cannot modify the status field';
  END IF;
  
  IF NEW.processed_at IS DISTINCT FROM OLD.processed_at THEN
    RAISE EXCEPTION 'You cannot modify the processed_at field';
  END IF;
  
  IF NEW.processed_by IS DISTINCT FROM OLD.processed_by THEN
    RAISE EXCEPTION 'You cannot modify the processed_by field';
  END IF;
  
  IF NEW.admin_notes IS DISTINCT FROM OLD.admin_notes THEN
    RAISE EXCEPTION 'You cannot modify the admin_notes field';
  END IF;
  
  RETURN NEW;
END;
$$;

-- Create trigger to enforce update restrictions
DROP TRIGGER IF EXISTS enforce_private_seed_str_application_update ON public.private_seed_str_applications;
CREATE TRIGGER enforce_private_seed_str_application_update
  BEFORE UPDATE ON public.private_seed_str_applications
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_private_seed_str_application_update();

-- Create a new RLS policy for users to update only their own applications
-- The trigger above will enforce which fields they can actually modify
CREATE POLICY "Users can update own applications with restrictions"
  ON public.private_seed_str_applications
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);