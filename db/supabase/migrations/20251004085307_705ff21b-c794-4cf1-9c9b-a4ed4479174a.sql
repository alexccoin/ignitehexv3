-- Create referrals table
CREATE TABLE IF NOT EXISTS public.referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id UUID NOT NULL,
  referred_id UUID NOT NULL,
  reward_amount NUMERIC DEFAULT 0,
  reward_claimed BOOLEAN DEFAULT false,
  claimed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  status TEXT NOT NULL DEFAULT 'pending',
  CONSTRAINT fk_referrer FOREIGN KEY (referrer_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT fk_referred FOREIGN KEY (referred_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT unique_referral UNIQUE(referrer_id, referred_id)
);

-- Enable RLS
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

-- Users can view their own referrals (as referrer)
CREATE POLICY "Users can view their referrals"
ON public.referrals
FOR SELECT
USING (auth.uid() = referrer_id);

-- Users can insert referrals where they are the referred user
CREATE POLICY "Users can be referred"
ON public.referrals
FOR INSERT
WITH CHECK (auth.uid() = referred_id);

-- Admins can view all referrals
CREATE POLICY "Admins can view all referrals"
ON public.referrals
FOR SELECT
USING (has_role(auth.uid(), 'admin'::app_role));

-- Admins can manage all referrals
CREATE POLICY "Admins can manage referrals"
ON public.referrals
FOR ALL
USING (has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- Create index for faster queries
CREATE INDEX idx_referrals_referrer ON public.referrals(referrer_id);
CREATE INDEX idx_referrals_referred ON public.referrals(referred_id);
CREATE INDEX idx_referrals_status ON public.referrals(status);

-- Add referral_code to user_profiles if not exists
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'user_profiles' 
    AND column_name = 'referral_code'
  ) THEN
    ALTER TABLE public.user_profiles 
    ADD COLUMN referral_code TEXT UNIQUE DEFAULT substring(md5(random()::text || gen_random_uuid()::text) from 1 for 8);
  END IF;
END $$;

-- Add referred_by to user_profiles if not exists
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'user_profiles' 
    AND column_name = 'referred_by'
  ) THEN
    ALTER TABLE public.user_profiles 
    ADD COLUMN referred_by UUID REFERENCES auth.users(id);
  END IF;
END $$;