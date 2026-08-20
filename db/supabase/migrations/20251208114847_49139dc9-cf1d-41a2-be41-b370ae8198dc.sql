-- Create merchant products table for marketplace
CREATE TABLE public.merchant_products (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  merchant_id UUID NOT NULL REFERENCES public.merchant_accounts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  product_name TEXT NOT NULL,
  description TEXT,
  price NUMERIC NOT NULL CHECK (price >= 0),
  price_currency TEXT NOT NULL DEFAULT 'EUR',
  crypto_price NUMERIC,
  crypto_currency TEXT CHECK (crypto_currency IN ('STR', 'wSTR', 'CCOS', 'ARSS')),
  category TEXT,
  image_url TEXT,
  stock_quantity INTEGER,
  is_digital BOOLEAN DEFAULT false,
  is_active BOOLEAN DEFAULT true,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create POS transactions table
CREATE TABLE public.pos_transactions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  merchant_id UUID NOT NULL REFERENCES public.merchant_accounts(id) ON DELETE CASCADE,
  merchant_user_id UUID NOT NULL,
  customer_user_id UUID,
  product_id UUID REFERENCES public.merchant_products(id) ON DELETE SET NULL,
  amount NUMERIC NOT NULL CHECK (amount > 0),
  currency TEXT NOT NULL CHECK (currency IN ('STR', 'wSTR', 'CCOS', 'ARSS')),
  fiat_equivalent NUMERIC,
  fiat_currency TEXT DEFAULT 'EUR',
  exchange_rate NUMERIC,
  reference_id TEXT NOT NULL,
  description TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'refunded')),
  payment_method TEXT DEFAULT 'crypto_wallet',
  metadata JSONB DEFAULT '{}',
  completed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create business IBANs table for merchant multi-currency accounts
CREATE TABLE public.merchant_business_ibans (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  merchant_id UUID NOT NULL REFERENCES public.merchant_accounts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  iban TEXT NOT NULL,
  bic TEXT NOT NULL,
  currency TEXT NOT NULL CHECK (currency IN ('EUR', 'USD', 'CHF', 'GBP')),
  account_holder TEXT NOT NULL,
  balance NUMERIC NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'frozen', 'closed')),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Add indexes for better performance
CREATE INDEX idx_merchant_products_merchant_id ON public.merchant_products(merchant_id);
CREATE INDEX idx_merchant_products_is_active ON public.merchant_products(is_active);
CREATE INDEX idx_pos_transactions_merchant_id ON public.pos_transactions(merchant_id);
CREATE INDEX idx_pos_transactions_status ON public.pos_transactions(status);
CREATE INDEX idx_pos_transactions_reference_id ON public.pos_transactions(reference_id);
CREATE INDEX idx_merchant_business_ibans_merchant_id ON public.merchant_business_ibans(merchant_id);

-- Enable RLS
ALTER TABLE public.merchant_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_business_ibans ENABLE ROW LEVEL SECURITY;

-- RLS Policies for merchant_products
CREATE POLICY "Users can view active products" ON public.merchant_products
  FOR SELECT USING (is_active = true);

CREATE POLICY "Merchants can manage their products" ON public.merchant_products
  FOR ALL USING (auth.uid() = user_id);

-- RLS Policies for pos_transactions
CREATE POLICY "Merchants can view their transactions" ON public.pos_transactions
  FOR SELECT USING (auth.uid() = merchant_user_id);

CREATE POLICY "Merchants can create transactions" ON public.pos_transactions
  FOR INSERT WITH CHECK (auth.uid() = merchant_user_id);

CREATE POLICY "Merchants can update their transactions" ON public.pos_transactions
  FOR UPDATE USING (auth.uid() = merchant_user_id);

-- RLS Policies for merchant_business_ibans
CREATE POLICY "Merchants can view their IBANs" ON public.merchant_business_ibans
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Admins can manage all merchant IBANs" ON public.merchant_business_ibans
  FOR ALL USING (EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role = 'admin'));

-- Update triggers
CREATE TRIGGER update_merchant_products_updated_at
  BEFORE UPDATE ON public.merchant_products
  FOR EACH ROW
  EXECUTE FUNCTION public.update_business_profiles_updated_at();

CREATE TRIGGER update_pos_transactions_updated_at
  BEFORE UPDATE ON public.pos_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_business_profiles_updated_at();

CREATE TRIGGER update_merchant_business_ibans_updated_at
  BEFORE UPDATE ON public.merchant_business_ibans
  FOR EACH ROW
  EXECUTE FUNCTION public.update_business_profiles_updated_at();