-- Create enhanced user profile connections table
CREATE TABLE public.user_profile_connections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  str_domain TEXT,
  iban_account_id UUID,
  visa_card_number TEXT,
  visa_card_status TEXT DEFAULT 'pending',
  sourceless_account_id TEXT,
  sourceless_wallet_address TEXT,
  ccoin_pool_balance DECIMAL(18,8) DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id)
);

-- Create IBAN accounts table
CREATE TABLE public.iban_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  iban TEXT NOT NULL UNIQUE,
  bic TEXT NOT NULL,
  account_holder TEXT NOT NULL,
  account_type TEXT NOT NULL,
  country_code TEXT NOT NULL,
  currency TEXT NOT NULL,
  balance DECIMAL(18,8) DEFAULT 0,
  status TEXT DEFAULT 'active',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Create transfer reports table
CREATE TABLE public.transfer_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  from_account_type TEXT NOT NULL, -- 'iban', 'sourceless', 'ccoin_pool'
  from_account_id TEXT NOT NULL,
  to_account_type TEXT NOT NULL,
  to_account_id TEXT NOT NULL,
  amount DECIMAL(18,8) NOT NULL,
  currency TEXT NOT NULL,
  exchange_rate DECIMAL(10,6),
  fee_amount DECIMAL(18,8) DEFAULT 0,
  reference TEXT,
  status TEXT DEFAULT 'pending',
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Create CCoin pool connections table
CREATE TABLE public.ccoin_pool_connections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  iban_account_id UUID NOT NULL REFERENCES public.iban_accounts(id) ON DELETE CASCADE,
  pool_type TEXT NOT NULL, -- 'main', 'reserve', 'operations'
  allocation_percentage DECIMAL(5,2) DEFAULT 100.00,
  auto_transfer_enabled BOOLEAN DEFAULT true,
  min_transfer_amount DECIMAL(18,8) DEFAULT 1000,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(iban_account_id, pool_type)
);

-- Enable RLS on all tables
ALTER TABLE public.user_profile_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.iban_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transfer_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ccoin_pool_connections ENABLE ROW LEVEL SECURITY;

-- RLS Policies for user_profile_connections
CREATE POLICY "Users can view their own profile connections" 
ON public.user_profile_connections 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own profile connections" 
ON public.user_profile_connections 
FOR UPDATE 
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own profile connections" 
ON public.user_profile_connections 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can manage all profile connections" 
ON public.user_profile_connections 
FOR ALL 
USING (is_admin(auth.uid()));

-- RLS Policies for iban_accounts
CREATE POLICY "Users can view their own IBAN accounts" 
ON public.iban_accounts 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own IBAN accounts" 
ON public.iban_accounts 
FOR UPDATE 
USING (auth.uid() = user_id);

CREATE POLICY "Admins can manage all IBAN accounts" 
ON public.iban_accounts 
FOR ALL 
USING (is_admin(auth.uid()));

-- RLS Policies for transfer_reports
CREATE POLICY "Users can view their own transfer reports" 
ON public.transfer_reports 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "System can insert transfer reports" 
ON public.transfer_reports 
FOR INSERT 
WITH CHECK (true);

CREATE POLICY "Admins can manage all transfer reports" 
ON public.transfer_reports 
FOR ALL 
USING (is_admin(auth.uid()));

-- RLS Policies for ccoin_pool_connections
CREATE POLICY "Users can view pool connections for their IBANs" 
ON public.ccoin_pool_connections 
FOR SELECT 
USING (EXISTS (
  SELECT 1 FROM public.iban_accounts ia 
  WHERE ia.id = iban_account_id AND ia.user_id = auth.uid()
));

CREATE POLICY "Admins can manage all pool connections" 
ON public.ccoin_pool_connections 
FOR ALL 
USING (is_admin(auth.uid()));

-- Function to auto-create profile connections on user signup
CREATE OR REPLACE FUNCTION public.create_user_profile_connections()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  sourceless_id TEXT;
  wallet_addr TEXT;
BEGIN
  -- Generate sourceless account ID
  sourceless_id := 'sl_' || substr(md5(random()::text || clock_timestamp()::text), 1, 24);
  
  -- Generate sourceless wallet address
  wallet_addr := 'slw_' || substr(md5(random()::text || clock_timestamp()::text), 1, 32);
  
  -- Create profile connections
  INSERT INTO public.user_profile_connections (
    user_id,
    sourceless_account_id,
    sourceless_wallet_address,
    ccoin_pool_balance
  ) VALUES (
    NEW.id,
    sourceless_id,
    wallet_addr,
    0
  );
  
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Log error but don't block signup
  RAISE LOG 'Error in create_user_profile_connections: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- Trigger to create profile connections on user signup
CREATE TRIGGER on_user_signup_create_connections
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.create_user_profile_connections();

-- Function to link IBAN to CCoin pool
CREATE OR REPLACE FUNCTION public.link_iban_to_pool(
  iban_id UUID,
  pool_type_param TEXT DEFAULT 'main'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  INSERT INTO public.ccoin_pool_connections (
    iban_account_id,
    pool_type,
    allocation_percentage,
    auto_transfer_enabled
  ) VALUES (
    iban_id,
    pool_type_param,
    100.00,
    true
  ) ON CONFLICT (iban_account_id, pool_type) DO NOTHING;
  
  RETURN TRUE;
END;
$$;

-- Function to get user's complete financial profile
CREATE OR REPLACE FUNCTION public.get_user_financial_profile(target_user_id UUID)
RETURNS TABLE(
  profile_id UUID,
  str_domain TEXT,
  iban_accounts JSONB,
  visa_card_info JSONB,
  sourceless_account JSONB,
  ccoin_pool_balance DECIMAL,
  recent_transfers JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    upc.id as profile_id,
    upc.str_domain,
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', ia.id,
          'iban', ia.iban,
          'bic', ia.bic,
          'account_holder', ia.account_holder,
          'account_type', ia.account_type,
          'currency', ia.currency,
          'balance', ia.balance,
          'status', ia.status
        )
      )
      FROM public.iban_accounts ia 
      WHERE ia.user_id = target_user_id
    ) as iban_accounts,
    jsonb_build_object(
      'card_number', upc.visa_card_number,
      'status', upc.visa_card_status
    ) as visa_card_info,
    jsonb_build_object(
      'account_id', upc.sourceless_account_id,
      'wallet_address', upc.sourceless_wallet_address
    ) as sourceless_account,
    upc.ccoin_pool_balance,
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', tr.id,
          'from_type', tr.from_account_type,
          'to_type', tr.to_account_type,
          'amount', tr.amount,
          'currency', tr.currency,
          'status', tr.status,
          'created_at', tr.created_at
        )
        ORDER BY tr.created_at DESC
      )
      FROM public.transfer_reports tr 
      WHERE tr.user_id = target_user_id
      LIMIT 10
    ) as recent_transfers
  FROM public.user_profile_connections upc
  WHERE upc.user_id = target_user_id;
END;
$$;