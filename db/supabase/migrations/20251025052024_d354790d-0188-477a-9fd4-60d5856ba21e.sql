-- Create fiat_wallets table to track user balances for each fiat currency
CREATE TABLE IF NOT EXISTS public.fiat_wallets (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  currency TEXT NOT NULL CHECK (currency IN ('EUR', 'CHF', 'GBP', 'USD')),
  balance NUMERIC NOT NULL DEFAULT 0 CHECK (balance >= 0),
  available_balance NUMERIC NOT NULL DEFAULT 0 CHECK (available_balance >= 0),
  held_balance NUMERIC NOT NULL DEFAULT 0 CHECK (held_balance >= 0),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id, currency)
);

-- Create fiat_transactions table for tracking all fiat transfers
CREATE TABLE IF NOT EXISTS public.fiat_transactions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  tx_id TEXT NOT NULL UNIQUE,
  from_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  to_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  from_identifier TEXT NOT NULL,
  to_identifier TEXT NOT NULL,
  currency TEXT NOT NULL CHECK (currency IN ('EUR', 'CHF', 'GBP', 'USD')),
  amount NUMERIC NOT NULL CHECK (amount > 0),
  fee NUMERIC NOT NULL DEFAULT 0,
  transfer_type TEXT NOT NULL CHECK (transfer_type IN ('user_to_user', 'user_to_iban', 'card_to_card', 'escrow')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'escrowed', 'released', 'cancelled')),
  requires_approval BOOLEAN NOT NULL DEFAULT false,
  approved_by UUID REFERENCES auth.users(id),
  approved_at TIMESTAMP WITH TIME ZONE,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  completed_at TIMESTAMP WITH TIME ZONE
);

-- Create crypto_wallets table for crypto balances
CREATE TABLE IF NOT EXISTS public.crypto_wallets (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_type TEXT NOT NULL CHECK (token_type IN ('CCOS', 'STARW', 'ARSS', 'HEX')),
  balance NUMERIC NOT NULL DEFAULT 0 CHECK (balance >= 0),
  available_balance NUMERIC NOT NULL DEFAULT 0 CHECK (available_balance >= 0),
  held_balance NUMERIC NOT NULL DEFAULT 0 CHECK (held_balance >= 0),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id, token_type)
);

-- Enable RLS
ALTER TABLE public.fiat_wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fiat_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crypto_wallets ENABLE ROW LEVEL SECURITY;

-- Fiat wallets policies
CREATE POLICY "Users can view their own fiat wallets"
ON public.fiat_wallets FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all fiat wallets"
ON public.fiat_wallets FOR SELECT
USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "System can manage fiat wallets"
ON public.fiat_wallets FOR ALL
USING (true)
WITH CHECK (true);

-- Fiat transactions policies
CREATE POLICY "Users can view their own fiat transactions"
ON public.fiat_transactions FOR SELECT
USING (auth.uid() = from_user_id OR auth.uid() = to_user_id);

CREATE POLICY "Users can create fiat transactions"
ON public.fiat_transactions FOR INSERT
WITH CHECK (auth.uid() = from_user_id);

CREATE POLICY "Admins can view all fiat transactions"
ON public.fiat_transactions FOR SELECT
USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can update fiat transactions"
ON public.fiat_transactions FOR UPDATE
USING (has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- Crypto wallets policies
CREATE POLICY "Users can view their own crypto wallets"
ON public.crypto_wallets FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all crypto wallets"
ON public.crypto_wallets FOR SELECT
USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "System can manage crypto wallets"
ON public.crypto_wallets FOR ALL
USING (true)
WITH CHECK (true);

-- Create indexes for performance
CREATE INDEX idx_fiat_wallets_user_id ON public.fiat_wallets(user_id);
CREATE INDEX idx_fiat_wallets_currency ON public.fiat_wallets(currency);
CREATE INDEX idx_fiat_transactions_from_user ON public.fiat_transactions(from_user_id);
CREATE INDEX idx_fiat_transactions_to_user ON public.fiat_transactions(to_user_id);
CREATE INDEX idx_fiat_transactions_status ON public.fiat_transactions(status);
CREATE INDEX idx_crypto_wallets_user_id ON public.crypto_wallets(user_id);
CREATE INDEX idx_crypto_wallets_token ON public.crypto_wallets(token_type);

-- Create trigger for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_fiat_wallets_updated_at
BEFORE UPDATE ON public.fiat_wallets
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_crypto_wallets_updated_at
BEFORE UPDATE ON public.crypto_wallets
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();