-- Create arx_club_members table
CREATE TABLE IF NOT EXISTS public.arx_club_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  membership_tier TEXT NOT NULL DEFAULT 'standard',
  status TEXT NOT NULL DEFAULT 'active',
  joined_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  expires_at TIMESTAMP WITH TIME ZONE,
  benefits JSONB DEFAULT '{}',
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id)
);

-- Enable RLS
ALTER TABLE public.arx_club_members ENABLE ROW LEVEL SECURITY;

-- Users can view their own membership
CREATE POLICY "Users can view own arx club membership"
  ON public.arx_club_members
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Users can insert their own membership (for future self-registration)
CREATE POLICY "Users can create own arx club membership"
  ON public.arx_club_members
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Admins can manage all memberships
CREATE POLICY "Admins can manage all arx club memberships"
  ON public.arx_club_members
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'admin'
    )
  );

-- Create updated_at trigger
CREATE OR REPLACE FUNCTION public.update_arx_club_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE TRIGGER update_arx_club_members_updated_at
  BEFORE UPDATE ON public.arx_club_members
  FOR EACH ROW
  EXECUTE FUNCTION public.update_arx_club_updated_at();

-- Add index for faster queries
CREATE INDEX IF NOT EXISTS idx_arx_club_members_user_id ON public.arx_club_members(user_id);
CREATE INDEX IF NOT EXISTS idx_arx_club_members_status ON public.arx_club_members(status);

-- Add audit logging for membership changes
INSERT INTO public.security_audit_log (
  user_id, 
  action, 
  resource_type, 
  details
) VALUES (
  auth.uid(),
  'arx_club_table_created',
  'database_migration',
  jsonb_build_object(
    'timestamp', now(),
    'description', 'ARX Club membership table initialized'
  )
);