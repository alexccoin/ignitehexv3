-- Create supernode_purchases table for institutional offering
CREATE TABLE IF NOT EXISTS supernode_purchases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id),
  full_name text NOT NULL,
  email_address text NOT NULL,
  str_domain text,
  company_name text,
  package_type text NOT NULL, -- 'basic', 'institutional', 'sovereign', 'cosmic'
  supernode_count integer NOT NULL DEFAULT 1,
  total_cost numeric NOT NULL,
  btc_amount numeric,
  eth_amount numeric,
  crypto_prices_at_purchase jsonb,
  transaction_hash text,
  stage integer DEFAULT 0,
  status text DEFAULT 'pending',
  created_at timestamptz DEFAULT now(),
  processed_at timestamptz,
  processed_by uuid REFERENCES auth.users(id)
);

-- Enable RLS
ALTER TABLE supernode_purchases ENABLE ROW LEVEL SECURITY;

-- Users can view their own supernode purchases
CREATE POLICY "Users can view own supernode purchases"
ON supernode_purchases FOR SELECT
USING (auth.uid() = user_id);

-- Users can insert their own supernode purchases
CREATE POLICY "Users can create own supernode purchases"
ON supernode_purchases FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Admins can view all supernode purchases
CREATE POLICY "Admins can view all supernode purchases"
ON supernode_purchases FOR SELECT
USING (has_role(auth.uid(), 'admin'::app_role));

-- Admins can update supernode purchases
CREATE POLICY "Admins can update supernode purchases"
ON supernode_purchases FOR UPDATE
USING (has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- Create index for faster queries
CREATE INDEX idx_supernode_purchases_user_id ON supernode_purchases(user_id);
CREATE INDEX idx_supernode_purchases_status ON supernode_purchases(status);
CREATE INDEX idx_supernode_purchases_created_at ON supernode_purchases(created_at DESC);