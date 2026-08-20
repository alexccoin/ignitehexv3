-- Create affiliate tracking table
CREATE TABLE public.seed_str_affiliates (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  affiliate_code TEXT NOT NULL UNIQUE,
  str_domain TEXT NOT NULL,
  full_name TEXT NOT NULL,
  email TEXT NOT NULL,
  total_referrals INTEGER DEFAULT 0,
  total_conversions INTEGER DEFAULT 0,
  total_investment_referred NUMERIC DEFAULT 0,
  status TEXT DEFAULT 'active',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create referral tracking table
CREATE TABLE public.seed_str_referrals (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  affiliate_id UUID NOT NULL REFERENCES public.seed_str_affiliates(id),
  referred_user_id UUID,
  application_id UUID,
  status TEXT DEFAULT 'pending',
  investment_amount NUMERIC DEFAULT 0,
  commission_amount NUMERIC DEFAULT 0,
  converted_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.seed_str_affiliates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seed_str_referrals ENABLE ROW LEVEL SECURITY;

-- Policies for affiliates table
CREATE POLICY "Users can view their own affiliate profile"
  ON public.seed_str_affiliates FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own affiliate profile"
  ON public.seed_str_affiliates FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view all affiliates"
  ON public.seed_str_affiliates FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role = 'admin'));

CREATE POLICY "Admins can manage all affiliates"
  ON public.seed_str_affiliates FOR ALL
  USING (EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role = 'admin'));

-- Policies for referrals table
CREATE POLICY "Users can view referrals for their affiliate"
  ON public.seed_str_referrals FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.seed_str_affiliates 
    WHERE id = affiliate_id AND user_id = auth.uid()
  ));

CREATE POLICY "Admins can view all referrals"
  ON public.seed_str_referrals FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role = 'admin'));

CREATE POLICY "Admins can manage all referrals"
  ON public.seed_str_referrals FOR ALL
  USING (EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role = 'admin'));

-- Allow inserts from anyone (for tracking referral clicks)
CREATE POLICY "Anyone can create referral entries"
  ON public.seed_str_referrals FOR INSERT
  WITH CHECK (true);

-- Add affiliate_id to seed_str_applications
ALTER TABLE public.seed_str_applications
ADD COLUMN IF NOT EXISTS affiliate_id UUID REFERENCES public.seed_str_affiliates(id);