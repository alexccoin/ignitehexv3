-- Create pending profile changes table for approval workflow
CREATE TABLE IF NOT EXISTS public.pending_profile_changes (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  requested_changes JSONB NOT NULL,
  change_reason TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'email_confirmed')),
  confirmation_token TEXT UNIQUE,
  token_expires_at TIMESTAMP WITH TIME ZONE,
  ip_address INET,
  user_agent TEXT,
  reviewed_by UUID REFERENCES auth.users(id),
  reviewed_at TIMESTAMP WITH TIME ZONE,
  admin_notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable Row Level Security
ALTER TABLE public.pending_profile_changes ENABLE ROW LEVEL SECURITY;

-- Users can view their own pending changes
CREATE POLICY "Users can view their own pending changes"
ON public.pending_profile_changes
FOR SELECT
USING (auth.uid() = user_id);

-- Users can insert their own pending changes
CREATE POLICY "Users can insert their own pending changes"
ON public.pending_profile_changes
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Admins can view all pending changes
CREATE POLICY "Admins can view all pending changes"
ON public.pending_profile_changes
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role = 'admin'
  )
);

-- Admins can update all pending changes
CREATE POLICY "Admins can update all pending changes"
ON public.pending_profile_changes
FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role = 'admin'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role = 'admin'
  )
);

-- Create indexes
CREATE INDEX idx_pending_profile_changes_user_id ON public.pending_profile_changes(user_id);
CREATE INDEX idx_pending_profile_changes_status ON public.pending_profile_changes(status);
CREATE INDEX idx_pending_profile_changes_token ON public.pending_profile_changes(confirmation_token);
CREATE INDEX idx_pending_profile_changes_created_at ON public.pending_profile_changes(created_at DESC);