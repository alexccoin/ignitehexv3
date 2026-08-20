-- Create founder pools table
CREATE TABLE public.founder_pools (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  pool_type TEXT NOT NULL CHECK (pool_type IN ('btc', 'ethereum', 'str', 'ccos', 'arss')),
  balance NUMERIC NOT NULL DEFAULT 0,
  usd_value NUMERIC NOT NULL DEFAULT 0,
  last_price NUMERIC NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create founder pool transactions table
CREATE TABLE public.founder_pool_transactions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  pool_type TEXT NOT NULL,
  transaction_type TEXT NOT NULL CHECK (transaction_type IN ('deposit', 'withdrawal', 'mint')),
  amount NUMERIC NOT NULL,
  ccos_minted NUMERIC DEFAULT 0,
  mint_percentage NUMERIC DEFAULT 0,
  usd_value_at_time NUMERIC NOT NULL DEFAULT 0,
  transaction_hash TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create founder access table
CREATE TABLE public.founder_access (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL UNIQUE,
  access_granted_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  last_access TIMESTAMP WITH TIME ZONE,
  is_active BOOLEAN NOT NULL DEFAULT true
);

-- Enable RLS
ALTER TABLE public.founder_pools ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.founder_pool_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.founder_access ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for founder_pools
CREATE POLICY "Users can view their own founder pools" 
ON public.founder_pools 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own founder pools" 
ON public.founder_pools 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own founder pools" 
ON public.founder_pools 
FOR UPDATE 
USING (auth.uid() = user_id);

-- Create RLS policies for founder_pool_transactions
CREATE POLICY "Users can view their own founder pool transactions" 
ON public.founder_pool_transactions 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own founder pool transactions" 
ON public.founder_pool_transactions 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Create RLS policies for founder_access
CREATE POLICY "Users can view their own founder access" 
ON public.founder_access 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own founder access" 
ON public.founder_access 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Create triggers for updated_at
CREATE TRIGGER update_founder_pools_updated_at
BEFORE UPDATE ON public.founder_pools
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_founder_pool_transactions_updated_at
BEFORE UPDATE ON public.founder_pool_transactions
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- Create function to calculate CCOS minting
CREATE OR REPLACE FUNCTION public.calculate_ccos_mint(
  pool_amount NUMERIC,
  pool_type TEXT,
  current_price NUMERIC
) RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  usd_value NUMERIC;
  mint_percentage NUMERIC;
  ccos_amount NUMERIC;
BEGIN
  -- Calculate USD value
  usd_value := pool_amount * current_price;
  
  -- Random mint percentage between 12.5% and 17.5%
  mint_percentage := 12.5 + (random() * 5.0);
  
  -- Calculate CCOS to mint (assuming 1 CCOS = $1 for simplicity)
  ccos_amount := (usd_value * mint_percentage / 100);
  
  RETURN ccos_amount;
END;
$$;