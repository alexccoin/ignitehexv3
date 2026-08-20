-- Create profile changes history table for tracking user profile modifications
CREATE TABLE IF NOT EXISTS public.profile_changes (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  changed_by UUID NOT NULL REFERENCES auth.users(id),
  field_name TEXT NOT NULL,
  old_value TEXT,
  new_value TEXT,
  change_reason TEXT,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable Row Level Security
ALTER TABLE public.profile_changes ENABLE ROW LEVEL SECURITY;

-- Users can view their own profile changes
CREATE POLICY "Users can view their own profile changes"
ON public.profile_changes
FOR SELECT
USING (auth.uid() = user_id);

-- Users can insert their own profile changes
CREATE POLICY "Users can insert their own profile changes"
ON public.profile_changes
FOR INSERT
WITH CHECK (auth.uid() = changed_by);

-- Admins can view all profile changes
CREATE POLICY "Admins can view all profile changes"
ON public.profile_changes
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role = 'admin'
  )
);

-- Create indexes for better performance
CREATE INDEX idx_profile_changes_user_id ON public.profile_changes(user_id);
CREATE INDEX idx_profile_changes_created_at ON public.profile_changes(created_at DESC);
CREATE INDEX idx_profile_changes_changed_by ON public.profile_changes(changed_by);