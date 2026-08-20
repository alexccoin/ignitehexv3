-- Create vesting_tokens table to track tokens in vesting period
CREATE TABLE public.vesting_tokens (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  token_type TEXT NOT NULL CHECK (token_type IN ('str', 'arss', 'ccos', 'starw')),
  amount NUMERIC NOT NULL DEFAULT 0,
  vesting_start_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  vesting_end_date TIMESTAMP WITH TIME ZONE NOT NULL,
  vesting_months INTEGER NOT NULL DEFAULT 6,
  source TEXT NOT NULL DEFAULT 'voucher',
  source_id UUID, -- reference to voucher_redemptions or other source
  status TEXT NOT NULL DEFAULT 'vesting' CHECK (status IN ('vesting', 'vested', 'staked', 'cancelled')),
  released_at TIMESTAMP WITH TIME ZONE,
  released_to_staking_pool_id UUID,
  metadata JSONB,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.vesting_tokens ENABLE ROW LEVEL SECURITY;

-- Users can view their own vesting tokens
CREATE POLICY "Users view own vesting tokens"
  ON public.vesting_tokens
  FOR SELECT
  USING (auth.uid() = user_id);

-- Admins can view all vesting tokens
CREATE POLICY "Admins view all vesting tokens"
  ON public.vesting_tokens
  FOR SELECT
  USING (has_role(auth.uid(), 'admin'::app_role));

-- Admins can insert vesting tokens
CREATE POLICY "Admins insert vesting tokens"
  ON public.vesting_tokens
  FOR INSERT
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- Admins can update vesting tokens
CREATE POLICY "Admins update vesting tokens"
  ON public.vesting_tokens
  FOR UPDATE
  USING (has_role(auth.uid(), 'admin'::app_role));

-- Create index for faster queries
CREATE INDEX idx_vesting_tokens_user_id ON public.vesting_tokens(user_id);
CREATE INDEX idx_vesting_tokens_status ON public.vesting_tokens(status);
CREATE INDEX idx_vesting_tokens_vesting_end_date ON public.vesting_tokens(vesting_end_date);

-- Create trigger for updated_at
CREATE TRIGGER update_vesting_tokens_updated_at
  BEFORE UPDATE ON public.vesting_tokens
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();