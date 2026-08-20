-- Create table for domain wallets (Sourceless wallets for each domain)
CREATE TABLE IF NOT EXISTS domain_wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  domain_id UUID NOT NULL REFERENCES str_domains(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  wallet_address TEXT NOT NULL UNIQUE,
  private_key_encrypted TEXT NOT NULL,
  public_key TEXT NOT NULL,
  wallet_type TEXT NOT NULL DEFAULT 'sourceless',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  status TEXT NOT NULL DEFAULT 'active',
  metadata JSONB DEFAULT '{}'::jsonb
);

-- Create table for domain node assignments
CREATE TABLE IF NOT EXISTS domain_nodes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  domain_id UUID NOT NULL REFERENCES str_domains(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  wallet_id UUID NOT NULL REFERENCES domain_wallets(id) ON DELETE CASCADE,
  node_type TEXT NOT NULL DEFAULT 'personal',
  is_active BOOLEAN DEFAULT true,
  is_primary BOOLEAN DEFAULT false,
  assigned_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  last_sync TIMESTAMP WITH TIME ZONE,
  node_status TEXT NOT NULL DEFAULT 'online',
  performance_metrics JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create table for domain profile assignments
CREATE TABLE IF NOT EXISTS user_domain_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  domain_id UUID NOT NULL REFERENCES str_domains(id) ON DELETE CASCADE,
  is_primary_domain BOOLEAN DEFAULT false,
  display_order INTEGER DEFAULT 0,
  visibility TEXT NOT NULL DEFAULT 'public',
  assigned_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id, domain_id)
);

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_domain_wallets_domain_id ON domain_wallets(domain_id);
CREATE INDEX IF NOT EXISTS idx_domain_wallets_user_id ON domain_wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_domain_wallets_wallet_address ON domain_wallets(wallet_address);
CREATE INDEX IF NOT EXISTS idx_domain_nodes_domain_id ON domain_nodes(domain_id);
CREATE INDEX IF NOT EXISTS idx_domain_nodes_user_id ON domain_nodes(user_id);
CREATE INDEX IF NOT EXISTS idx_domain_nodes_wallet_id ON domain_nodes(wallet_id);
CREATE INDEX IF NOT EXISTS idx_user_domain_profiles_user_id ON user_domain_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_domain_profiles_domain_id ON user_domain_profiles(domain_id);

-- Enable Row Level Security
ALTER TABLE domain_wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE domain_nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_domain_profiles ENABLE ROW LEVEL SECURITY;

-- RLS Policies for domain_wallets
CREATE POLICY "Users can view their own domain wallets"
  ON domain_wallets FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all domain wallets"
  ON domain_wallets FOR SELECT
  USING (is_admin(auth.uid()));

CREATE POLICY "Admins can create domain wallets"
  ON domain_wallets FOR INSERT
  WITH CHECK (is_admin(auth.uid()));

CREATE POLICY "Admins can update domain wallets"
  ON domain_wallets FOR UPDATE
  USING (is_admin(auth.uid()));

-- RLS Policies for domain_nodes
CREATE POLICY "Users can view their own domain nodes"
  ON domain_nodes FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all domain nodes"
  ON domain_nodes FOR SELECT
  USING (is_admin(auth.uid()));

CREATE POLICY "Admins can manage domain nodes"
  ON domain_nodes FOR ALL
  USING (is_admin(auth.uid()));

CREATE POLICY "Users can update their own domain nodes"
  ON domain_nodes FOR UPDATE
  USING (auth.uid() = user_id);

-- RLS Policies for user_domain_profiles
CREATE POLICY "Users can view their own domain profiles"
  ON user_domain_profiles FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can manage their own domain profiles"
  ON user_domain_profiles FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own domain profiles"
  ON user_domain_profiles FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own domain profiles"
  ON user_domain_profiles FOR DELETE
  USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all domain profiles"
  ON user_domain_profiles FOR SELECT
  USING (is_admin(auth.uid()));

-- Add trigger for updated_at
CREATE OR REPLACE FUNCTION update_domain_wallets_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER domain_wallets_updated_at
  BEFORE UPDATE ON domain_wallets
  FOR EACH ROW
  EXECUTE FUNCTION update_domain_wallets_updated_at();

CREATE TRIGGER domain_nodes_updated_at
  BEFORE UPDATE ON domain_nodes
  FOR EACH ROW
  EXECUTE FUNCTION update_domain_wallets_updated_at();

CREATE TRIGGER user_domain_profiles_updated_at
  BEFORE UPDATE ON user_domain_profiles
  FOR EACH ROW
  EXECUTE FUNCTION update_domain_wallets_updated_at();