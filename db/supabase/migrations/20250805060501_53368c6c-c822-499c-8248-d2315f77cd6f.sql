-- Create orders table to track CoinPayments transactions
CREATE TABLE public.crypto_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  token_symbol TEXT NOT NULL,
  package_amount_usd NUMERIC NOT NULL,
  token_amount NUMERIC NOT NULL,
  token_price_at_time NUMERIC NOT NULL,
  coinpayments_txn_id TEXT UNIQUE,
  payment_address TEXT,
  amount_to_pay NUMERIC,
  payment_currency TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  timeout_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable Row-Level Security
ALTER TABLE public.crypto_orders ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can view their own orders" 
ON public.crypto_orders 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own orders" 
ON public.crypto_orders 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "System can update orders" 
ON public.crypto_orders 
FOR UPDATE 
USING (true);

-- Create function to update timestamps
CREATE TRIGGER update_crypto_orders_updated_at
BEFORE UPDATE ON public.crypto_orders
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();