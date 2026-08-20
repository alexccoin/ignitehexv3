-- Create airdrop_registrations table
CREATE TABLE IF NOT EXISTS public.airdrop_registrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  email_address text NOT NULL,
  wallet_address text NOT NULL,
  requested_amount numeric NOT NULL DEFAULT 1000,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  tokens_credited boolean DEFAULT false,
  credited_amount numeric DEFAULT 0,
  credited_at timestamptz,
  processed_by uuid REFERENCES auth.users(id),
  processed_at timestamptz,
  admin_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.airdrop_registrations ENABLE ROW LEVEL SECURITY;

-- Users can insert their own registrations
CREATE POLICY "Users can create their own airdrop registrations"
ON public.airdrop_registrations
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Users can view their own registrations
CREATE POLICY "Users can view their own airdrop registrations"
ON public.airdrop_registrations
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Admins can view all registrations
CREATE POLICY "Admins can view all airdrop registrations"
ON public.airdrop_registrations
FOR SELECT
TO authenticated
USING (has_role(auth.uid(), 'admin'::app_role));

-- Admins can update all registrations
CREATE POLICY "Admins can update all airdrop registrations"
ON public.airdrop_registrations
FOR UPDATE
TO authenticated
USING (has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- Create index for performance
CREATE INDEX idx_airdrop_registrations_user_id ON public.airdrop_registrations(user_id);
CREATE INDEX idx_airdrop_registrations_status ON public.airdrop_registrations(status);