-- Create table for PIN reset OTPs
CREATE TABLE IF NOT EXISTS public.pin_reset_otps (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  otp_hash TEXT NOT NULL,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);

-- Enable RLS
ALTER TABLE public.pin_reset_otps ENABLE ROW LEVEL SECURITY;

-- Users can only view their own OTPs
CREATE POLICY "Users can view own OTPs"
  ON public.pin_reset_otps
  FOR SELECT
  USING (auth.uid() = user_id);

-- Users can insert their own OTPs (via edge function)
CREATE POLICY "Users can insert own OTPs"
  ON public.pin_reset_otps
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can delete their own expired OTPs
CREATE POLICY "Users can delete own OTPs"
  ON public.pin_reset_otps
  FOR DELETE
  USING (auth.uid() = user_id);

-- Add index for performance
CREATE INDEX idx_pin_reset_otps_user_expires 
  ON public.pin_reset_otps(user_id, expires_at DESC);

-- Add cleanup function to delete expired OTPs (runs periodically)
CREATE OR REPLACE FUNCTION cleanup_expired_otps()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM public.pin_reset_otps
  WHERE expires_at < now();
END;
$$;