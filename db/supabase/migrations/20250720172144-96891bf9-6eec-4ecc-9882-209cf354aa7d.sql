-- Create transactions table for ExCcoinLp withdrawals
CREATE TABLE public.transactions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  transaction_id TEXT NOT NULL UNIQUE,
  amount DECIMAL(15,2) NOT NULL,
  origin_wallet TEXT,
  receiver_wallet TEXT NOT NULL,
  full_name TEXT NOT NULL,
  email_address TEXT NOT NULL,
  invoice_number TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'processed', 'completed')),
  transaction_hash TEXT NOT NULL,
  btc_payout_amount DECIMAL(15,8) NOT NULL,
  ccos_pool_addition DECIMAL(15,8) NOT NULL,
  btc_price_at_time DECIMAL(15,2) NOT NULL,
  ccos_price_at_time DECIMAL(15,6) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  completed_at TIMESTAMP WITH TIME ZONE
);

-- Enable Row Level Security
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

-- Create policies for transactions
CREATE POLICY "Users can view their own transactions" 
ON public.transactions 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own transactions" 
ON public.transactions 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own transactions" 
ON public.transactions 
FOR UPDATE 
USING (auth.uid() = user_id);

-- Admin users can view all transactions
CREATE POLICY "Admin users can view all transactions" 
ON public.transactions 
FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE user_id = auth.uid() 
    AND role = 'admin'
  )
);

-- Create trigger for automatic timestamp updates
CREATE TRIGGER update_transactions_updated_at
BEFORE UPDATE ON public.transactions
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- Create indexes for better performance
CREATE INDEX idx_transactions_user_id ON public.transactions(user_id);
CREATE INDEX idx_transactions_status ON public.transactions(status);
CREATE INDEX idx_transactions_created_at ON public.transactions(created_at DESC);