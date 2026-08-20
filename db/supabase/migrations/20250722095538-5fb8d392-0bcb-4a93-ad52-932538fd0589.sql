-- Update founder pools to support founder positions
ALTER TABLE founder_pools ADD COLUMN IF NOT EXISTS founder_position_id uuid;
ALTER TABLE founder_pools ADD COLUMN IF NOT EXISTS is_founder_position boolean DEFAULT false;

-- Create founder positions table
CREATE TABLE IF NOT EXISTS public.founder_positions (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  position_number integer NOT NULL,
  current_usd_value numeric NOT NULL DEFAULT 0,
  max_usd_limit numeric NOT NULL DEFAULT 1000000,
  min_deposit_usd numeric NOT NULL DEFAULT 10000,
  status text NOT NULL DEFAULT 'active',
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT founder_positions_position_number_unique UNIQUE(position_number),
  CONSTRAINT founder_positions_max_usd_check CHECK (max_usd_limit <= 1000000),
  CONSTRAINT founder_positions_min_deposit_check CHECK (min_deposit_usd >= 10000),
  CONSTRAINT founder_positions_current_value_check CHECK (current_usd_value <= max_usd_limit)
);

-- Enable RLS on founder positions
ALTER TABLE public.founder_positions ENABLE ROW LEVEL SECURITY;

-- Create policies for founder positions
CREATE POLICY "Users can view their own founder positions" 
ON public.founder_positions 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own founder positions" 
ON public.founder_positions 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own founder positions" 
ON public.founder_positions 
FOR UPDATE 
USING (auth.uid() = user_id);

-- Update founder pool transactions to track founder positions
ALTER TABLE founder_pool_transactions ADD COLUMN IF NOT EXISTS founder_position_id uuid;
ALTER TABLE founder_pool_transactions ADD COLUMN IF NOT EXISTS is_founder_position boolean DEFAULT false;

-- Add constraint to only allow BTC and ETH for founder positions
ALTER TABLE founder_pool_transactions ADD CONSTRAINT founder_position_currency_check 
CHECK (
  (is_founder_position = false) OR 
  (is_founder_position = true AND pool_type IN ('btc', 'ethereum'))
);

-- Add constraint for minimum founder position deposit
ALTER TABLE founder_pool_transactions ADD CONSTRAINT founder_position_min_deposit_check 
CHECK (
  (is_founder_position = false) OR 
  (is_founder_position = true AND usd_value_at_time >= 10000)
);

-- Create trigger for updating founder positions
CREATE OR REPLACE FUNCTION public.update_founder_position()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_founder_position = true AND NEW.founder_position_id IS NOT NULL THEN
    UPDATE public.founder_positions 
    SET 
      current_usd_value = current_usd_value + NEW.usd_value_at_time,
      updated_at = now()
    WHERE id = NEW.founder_position_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER update_founder_position_trigger
  AFTER INSERT ON public.founder_pool_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_founder_position();

-- Add updated_at trigger for founder positions
CREATE TRIGGER update_founder_positions_updated_at
  BEFORE UPDATE ON public.founder_positions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();