-- Add payment tracking fields to seed_str_applications
ALTER TABLE public.seed_str_applications
ADD COLUMN IF NOT EXISTS payment_deadline timestamptz,
ADD COLUMN IF NOT EXISTS payment_status text DEFAULT 'awaiting_payment' CHECK (payment_status IN ('awaiting_payment', 'payment_submitted', 'payment_verified', 'payment_declined', 'payment_expired', 'cancelled')),
ADD COLUMN IF NOT EXISTS payment_submitted_at timestamptz,
ADD COLUMN IF NOT EXISTS payment_verified_at timestamptz,
ADD COLUMN IF NOT EXISTS payment_verified_by uuid,
ADD COLUMN IF NOT EXISTS payment_crypto text,
ADD COLUMN IF NOT EXISTS payment_amount numeric,
ADD COLUMN IF NOT EXISTS payment_hash text,
ADD COLUMN IF NOT EXISTS str_shares_credited numeric DEFAULT 0,
ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
ADD COLUMN IF NOT EXISTS cancelled_by uuid;

-- Create StrShares balance table for wNFT shares
CREATE TABLE IF NOT EXISTS public.user_str_shares (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  balance numeric NOT NULL DEFAULT 0,
  locked_balance numeric NOT NULL DEFAULT 0,
  vesting_end_date timestamptz,
  source_application_id uuid REFERENCES public.seed_str_applications(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id)
);

-- Enable RLS
ALTER TABLE public.user_str_shares ENABLE ROW LEVEL SECURITY;

-- Users can view their own shares
CREATE POLICY "Users can view own str shares"
ON public.user_str_shares FOR SELECT
USING (auth.uid() = user_id);

-- Only system can insert/update (via admin actions)
CREATE POLICY "System can manage str shares"
ON public.user_str_shares FOR ALL
USING (true)
WITH CHECK (true);

-- Create trigger for updated_at
CREATE TRIGGER update_user_str_shares_updated_at
BEFORE UPDATE ON public.user_str_shares
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- Add index for faster lookups
CREATE INDEX IF NOT EXISTS idx_user_str_shares_user_id ON public.user_str_shares(user_id);
CREATE INDEX IF NOT EXISTS idx_seed_str_applications_payment_status ON public.seed_str_applications(payment_status);