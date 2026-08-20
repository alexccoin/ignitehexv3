-- Create liquidity pools table
CREATE TABLE public.liquidity_pools (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_name TEXT NOT NULL,
  pool_symbol TEXT NOT NULL,
  base_token TEXT NOT NULL,
  quote_token TEXT NOT NULL DEFAULT 'CCOIN',
  total_liquidity_usd NUMERIC NOT NULL DEFAULT 0,
  total_volume_24h NUMERIC NOT NULL DEFAULT 0,
  apy NUMERIC NOT NULL DEFAULT 0,
  fee_percentage NUMERIC NOT NULL DEFAULT 0.3,
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
  usd_value_at_deposit NUMERIC NOT NULL DEFAULT 0,
  current_usd_value NUMERIC NOT NULL DEFAULT 0,
  rewards_earned NUMERIC NOT NULL DEFAULT 0,
  share_percentage NUMERIC NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create liquidity transactions table
CREATE TABLE public.liquidity_transactions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  pool_id UUID NOT NULL REFERENCES public.liquidity_pools(id),
  position_id UUID REFERENCES public.user_liquidity_positions(id),
  transaction_type TEXT NOT NULL CHECK (transaction_type IN ('deposit', 'withdraw', 'reward_claim')),
  amount NUMERIC NOT NULL,
  usd_value_at_time NUMERIC NOT NULL,
  transaction_hash TEXT,
  status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed')),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.liquidity_pools ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_liquidity_positions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.liquidity_transactions ENABLE ROW LEVEL SECURITY;

-- RLS Policies for liquidity_pools (public read, admin write)
CREATE POLICY "Anyone can view liquidity pools" 
ON public.liquidity_pools 
FOR SELECT 
USING (true);

CREATE POLICY "Only admins can manage liquidity pools" 
ON public.liquidity_pools 
FOR ALL 
USING (EXISTS (
  SELECT 1 FROM profiles 
  WHERE user_id = auth.uid() AND role = 'admin'
));

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

CREATE POLICY "Admins can view all positions" 
ON public.user_liquidity_positions 
FOR SELECT 
USING (EXISTS (
  SELECT 1 FROM profiles 
  WHERE user_id = auth.uid() AND role = 'admin'
));

-- RLS Policies for liquidity_transactions
CREATE POLICY "Users can view their own transactions" 
ON public.liquidity_transactions 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own transactions" 
ON public.liquidity_transactions 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view all transactions" 
ON public.liquidity_transactions 
FOR SELECT 
USING (EXISTS (
  SELECT 1 FROM profiles 
  WHERE user_id = auth.uid() AND role = 'admin'
));

-- Insert initial liquidity pools
INSERT INTO public.liquidity_pools (pool_name, pool_symbol, base_token, total_liquidity_usd, apy, fee_percentage) VALUES
('Bitcoin Liquidity Pool', 'BTC-CCOIN', 'BTC', 2500000.00, 8.5, 0.3),
('Ethereum Liquidity Pool', 'ETH-CCOIN', 'ETH', 1800000.00, 7.2, 0.3),
('Binance Coin Liquidity Pool', 'BNB-CCOIN', 'BNB', 950000.00, 9.1, 0.3);

-- Function to update liquidity pool stats
CREATE OR REPLACE FUNCTION public.update_liquidity_pool_stats()
RETURNS TRIGGER AS $$
BEGIN
  -- Update pool total liquidity and user share percentages
  UPDATE public.liquidity_pools 
  SET 
    total_liquidity_usd = (
      SELECT COALESCE(SUM(current_usd_value), 0) 
      FROM public.user_liquidity_positions 
      WHERE pool_id = COALESCE(NEW.pool_id, OLD.pool_id)
    ),
    updated_at = now()
  WHERE id = COALESCE(NEW.pool_id, OLD.pool_id);
  
  -- Update share percentages for all positions in this pool
  UPDATE public.user_liquidity_positions 
  SET 
    share_percentage = CASE 
      WHEN (SELECT total_liquidity_usd FROM public.liquidity_pools WHERE id = pool_id) > 0 
      THEN (current_usd_value / (SELECT total_liquidity_usd FROM public.liquidity_pools WHERE id = pool_id)) * 100
      ELSE 0 
    END,
    updated_at = now()
  WHERE pool_id = COALESCE(NEW.pool_id, OLD.pool_id);
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Triggers for automatic updates
CREATE TRIGGER update_liquidity_pools_updated_at
  BEFORE UPDATE ON public.liquidity_pools
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_user_liquidity_positions_updated_at
  BEFORE UPDATE ON public.user_liquidity_positions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_pool_stats_on_position_change
  AFTER INSERT OR UPDATE OR DELETE ON public.user_liquidity_positions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_liquidity_pool_stats();