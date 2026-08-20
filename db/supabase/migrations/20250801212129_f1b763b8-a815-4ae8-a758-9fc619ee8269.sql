-- Add wallet security fields to user_profiles table
ALTER TABLE public.user_profiles 
ADD COLUMN IF NOT EXISTS wallet_recovery_words TEXT[], -- Array of 13 recovery words
ADD COLUMN IF NOT EXISTS wallet_pin_hash TEXT, -- Hashed PIN for security
ADD COLUMN IF NOT EXISTS wallet_setup_completed BOOLEAN DEFAULT false, -- Track if wallet setup is done
ADD COLUMN IF NOT EXISTS wallet_created_at TIMESTAMP WITH TIME ZONE DEFAULT NULL; -- When wallet was created

-- Create a secure function to validate PIN
CREATE OR REPLACE FUNCTION public.validate_wallet_pin(user_uuid UUID, input_pin TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  stored_pin_hash TEXT;
BEGIN
  -- Get the stored PIN hash for the user
  SELECT wallet_pin_hash INTO stored_pin_hash
  FROM user_profiles
  WHERE user_id = user_uuid;
  
  -- Check if PIN hash matches (using simple hash for demo - in production use proper hashing)
  RETURN stored_pin_hash = encode(digest(input_pin, 'sha256'), 'hex');
END;
$$;

-- Create function to get recovery words (admin only or with PIN validation)
CREATE OR REPLACE FUNCTION public.get_wallet_recovery_words(user_uuid UUID, input_pin TEXT DEFAULT NULL)
RETURNS TEXT[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  recovery_words TEXT[];
  is_admin BOOLEAN;
BEGIN
  -- Check if user is admin
  SELECT is_admin(auth.uid()) INTO is_admin;
  
  -- If admin, return words without PIN check
  IF is_admin THEN
    SELECT wallet_recovery_words INTO recovery_words
    FROM user_profiles
    WHERE user_id = user_uuid;
    RETURN recovery_words;
  END IF;
  
  -- For regular users, validate PIN first
  IF input_pin IS NULL OR NOT validate_wallet_pin(user_uuid, input_pin) THEN
    RAISE EXCEPTION 'Invalid PIN or unauthorized access';
  END IF;
  
  -- Return recovery words if PIN is valid
  SELECT wallet_recovery_words INTO recovery_words
  FROM user_profiles
  WHERE user_id = user_uuid;
  
  RETURN recovery_words;
END;
$$;

-- Update RLS policies for new columns
CREATE POLICY "Users can update their wallet setup" ON public.user_profiles
FOR UPDATE USING (auth.uid() = user_id);

-- Create audit log for wallet operations
CREATE TABLE IF NOT EXISTS public.wallet_security_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  action TEXT NOT NULL, -- 'wallet_created', 'pin_verified', 'recovery_accessed', etc.
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

ALTER TABLE public.wallet_security_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own wallet logs" ON public.wallet_security_log
FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "System can insert wallet logs" ON public.wallet_security_log
FOR INSERT WITH CHECK (true);