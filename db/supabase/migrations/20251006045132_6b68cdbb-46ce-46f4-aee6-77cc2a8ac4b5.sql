-- Create wallet_transactions table for tracking all wallet transfers
CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  to_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  from_address TEXT NOT NULL,
  to_address TEXT NOT NULL,
  amount NUMERIC NOT NULL CHECK (amount > 0),
  token_type TEXT NOT NULL DEFAULT 'str',
  transaction_hash TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  failure_reason TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  CONSTRAINT valid_addresses CHECK (from_address != to_address)
);

-- Create index for efficient queries
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_from_user ON public.wallet_transactions(from_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_to_user ON public.wallet_transactions(to_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_status ON public.wallet_transactions(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_to_address ON public.wallet_transactions(to_address);

-- Enable RLS
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own transactions"
  ON public.wallet_transactions
  FOR SELECT
  USING (
    auth.uid() = from_user_id OR 
    auth.uid() = to_user_id OR
    is_admin(auth.uid())
  );

CREATE POLICY "Users can insert their own send transactions"
  ON public.wallet_transactions
  FOR INSERT
  WITH CHECK (auth.uid() = from_user_id AND auth.uid() IS NOT NULL);

CREATE POLICY "Admins can manage all transactions"
  ON public.wallet_transactions
  FOR ALL
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- Create pending_balance_locks table to prevent double spending
CREATE TABLE IF NOT EXISTS public.pending_balance_locks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_type TEXT NOT NULL,
  locked_amount NUMERIC NOT NULL CHECK (locked_amount > 0),
  transaction_id UUID NOT NULL REFERENCES public.wallet_transactions(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '5 minutes'),
  UNIQUE(transaction_id)
);

CREATE INDEX IF NOT EXISTS idx_pending_locks_user_token ON public.pending_balance_locks(user_id, token_type);
CREATE INDEX IF NOT EXISTS idx_pending_locks_expires ON public.pending_balance_locks(expires_at);

-- Enable RLS on pending_balance_locks
ALTER TABLE public.pending_balance_locks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own locks"
  ON public.pending_balance_locks
  FOR SELECT
  USING (auth.uid() = user_id OR is_admin(auth.uid()));

-- Function to get available balance (total balance minus locked amounts)
CREATE OR REPLACE FUNCTION get_available_balance(
  p_user_id UUID,
  p_token_type TEXT
)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_balance NUMERIC := 0;
  v_locked_balance NUMERIC := 0;
BEGIN
  -- Clean up expired locks first
  DELETE FROM pending_balance_locks WHERE expires_at < now();
  
  -- Get total balance from user_staking_pools
  SELECT COALESCE(balance, 0)
  INTO v_total_balance
  FROM user_staking_pools
  WHERE user_id = p_user_id AND pool_type = p_token_type;
  
  -- Get locked balance
  SELECT COALESCE(SUM(locked_amount), 0)
  INTO v_locked_balance
  FROM pending_balance_locks
  WHERE user_id = p_user_id 
    AND token_type = p_token_type
    AND expires_at > now();
  
  RETURN GREATEST(v_total_balance - v_locked_balance, 0);
END;
$$;

-- Function to resolve str.name to user_id
CREATE OR REPLACE FUNCTION resolve_str_address(p_address TEXT)
RETURNS TABLE(user_id UUID, full_address TEXT, address_type TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Check if it's a str.name domain
  IF p_address LIKE 'str.%' THEN
    RETURN QUERY
    SELECT 
      sd.user_id,
      sd.domain_name as full_address,
      'str_domain' as address_type
    FROM str_domains sd
    WHERE sd.domain_name = p_address 
      AND sd.status = 'minted'
      AND sd.is_active = true
    LIMIT 1;
  -- Check if it's a STR wallet address
  ELSIF LENGTH(p_address) >= 26 THEN
    RETURN QUERY
    SELECT 
      up.user_id,
      up.str_wallet_address as full_address,
      'str_wallet' as address_type
    FROM user_profiles up
    WHERE up.str_wallet_address = p_address
    LIMIT 1;
  END IF;
END;
$$;

-- Trigger to update wallet_transactions updated_at
CREATE OR REPLACE FUNCTION update_wallet_transaction_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  IF NEW.status IN ('completed', 'failed', 'cancelled') AND OLD.status = 'pending' THEN
    NEW.completed_at = now();
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER wallet_transactions_updated_at
  BEFORE UPDATE ON public.wallet_transactions
  FOR EACH ROW
  EXECUTE FUNCTION update_wallet_transaction_timestamp();

-- Log the migration
INSERT INTO security_audit_log (user_id, action, resource_type, details)
VALUES (
  auth.uid(),
  'wallet_system_migration',
  'database_migration',
  jsonb_build_object(
    'description', 'Created wallet_transactions and pending_balance_locks tables with double-spending protection',
    'timestamp', now()
  )
);