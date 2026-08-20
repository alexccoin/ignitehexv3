-- Create liquidity pools table
CREATE TABLE public.liquidity_pools (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_name TEXT NOT NULL,
  pool_symbol TEXT NOT NULL,
  total_liquidity NUMERIC NOT NULL DEFAULT 0,
  apy_rate NUMERIC NOT NULL DEFAULT 0,
  pool_type TEXT NOT NULL, -- 'btc', 'ethereum', 'binance'
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create user liquidity positions table
CREATE TABLE public.user_liquidity_positions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  pool_id UUID NOT NULL REFERENCES public.liquidity_pools(id),
  amount_deposited NUMERIC NOT NULL DEFAULT 0,
  share_percentage NUMERIC NOT NULL DEFAULT 0,
  rewards_earned NUMERIC NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create liquidity transactions table
CREATE TABLE public.liquidity_transactions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  pool_id UUID NOT NULL REFERENCES public.liquidity_pools(id),
  transaction_type TEXT NOT NULL, -- 'deposit', 'withdraw', 'reward'
  amount NUMERIC NOT NULL,
  transaction_hash TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.liquidity_pools ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_liquidity_positions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.liquidity_transactions ENABLE ROW LEVEL SECURITY;

-- RLS Policies for liquidity_pools (public view, admin manage)
CREATE POLICY "Anyone can view liquidity pools" 
ON public.liquidity_pools 
FOR SELECT 
USING (true);

CREATE POLICY "Only admins can manage liquidity pools" 
ON public.liquidity_pools 
FOR ALL 
USING (is_admin(auth.uid()));

-- RLS Policies for user_liquidity_positions
CREATE POLICY "Users can view their own positions" 
ON public.user_liquidity_positions 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own positions" 
ON public.user_liquidity_positions 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own positions" 
ON public.user_liquidity_positions 
FOR UPDATE 
USING (auth.uid() = user_id);

-- RLS Policies for liquidity_transactions
CREATE POLICY "Users can view their own transactions" 
ON public.liquidity_transactions 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own transactions" 
ON public.liquidity_transactions 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Insert initial liquidity pools
INSERT INTO public.liquidity_pools (pool_name, pool_symbol, total_liquidity, apy_rate, pool_type, description) VALUES
('Bitcoin Liquidity Pool', 'BTC-LP', 0, 8.5, 'btc', 'Earn rewards by providing Bitcoin liquidity to the CCoin Finance ecosystem'),
('Ethereum Liquidity Pool', 'ETH-LP', 0, 7.8, 'ethereum', 'Earn rewards by providing Ethereum liquidity to the CCoin Finance ecosystem'),
('Binance Coin Liquidity Pool', 'BNB-LP', 0, 9.2, 'binance', 'Earn rewards by providing BNB liquidity to the CCoin Finance ecosystem');

-- Function to update liquidity pool stats
CREATE OR REPLACE FUNCTION public.update_pool_stats(pool_uuid UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  total_deposits NUMERIC;
  total_positions INTEGER;
BEGIN
  -- Calculate total liquidity and update pool
  SELECT COALESCE(SUM(amount_deposited), 0), COUNT(*)
  INTO total_deposits, total_positions
  FROM user_liquidity_positions 
  WHERE pool_id = pool_uuid;
  
  UPDATE liquidity_pools 
  SET 
    total_liquidity = total_deposits,
    updated_at = now()
  WHERE id = pool_uuid;
END;
$function$;

-- Triggers for automatic timestamp updates
CREATE TRIGGER update_liquidity_pools_updated_at
  BEFORE UPDATE ON public.liquidity_pools
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_user_liquidity_positions_updated_at
  BEFORE UPDATE ON public.user_liquidity_positions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_liquidity_transactions_updated_at
  BEFORE UPDATE ON public.liquidity_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();