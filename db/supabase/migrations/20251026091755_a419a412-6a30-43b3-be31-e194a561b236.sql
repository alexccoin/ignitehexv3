-- Create dedicated CCoin network cards table
CREATE TABLE IF NOT EXISTS ccoin_network_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  str_domain TEXT NOT NULL,
  card_number TEXT NOT NULL UNIQUE,
  internal_iban TEXT NOT NULL UNIQUE,
  wallet_address TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'revoked')),
  issued_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  last_activity TIMESTAMP WITH TIME ZONE,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT card_number_length CHECK (char_length(card_number) <= 25),
  CONSTRAINT card_number_format CHECK (card_number ~ '^zk13\.str\.[a-z0-9]{1,16}$'),
  CONSTRAINT internal_iban_format CHECK (internal_iban ~ '^str\.zk13\.[a-z0-9]{1,16}$')
);

-- Create internal IBAN currency mappings (magnet addresses)
CREATE TABLE IF NOT EXISTS ccoin_internal_iban_currencies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id UUID NOT NULL REFERENCES ccoin_network_cards(id) ON DELETE CASCADE,
  internal_iban TEXT NOT NULL,
  currency TEXT NOT NULL CHECK (currency IN ('EUR', 'USD', 'CHF', 'GBP')),
  magnet_address TEXT NOT NULL UNIQUE,
  balance NUMERIC(20, 8) DEFAULT 0 CHECK (balance >= 0),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(card_id, currency),
  CONSTRAINT magnet_address_format CHECK (magnet_address ~ '^(EUR|USD|CHF|GBP)\.str\.zk13\.[a-z0-9]{1,16}$')
);

-- Create CCoin network transactions table
CREATE TABLE IF NOT EXISTS ccoin_network_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id UUID NOT NULL REFERENCES ccoin_network_cards(id) ON DELETE CASCADE,
  transaction_type TEXT NOT NULL CHECK (transaction_type IN ('deposit', 'withdrawal', 'transfer', 'payment')),
  from_address TEXT NOT NULL,
  to_address TEXT NOT NULL,
  amount NUMERIC(20, 8) NOT NULL CHECK (amount > 0),
  currency TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'cancelled')),
  tx_hash TEXT,
  validator_node TEXT,
  validated_at TIMESTAMP WITH TIME ZONE,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  completed_at TIMESTAMP WITH TIME ZONE
);

-- Create indexes for performance
CREATE INDEX idx_ccoin_cards_user ON ccoin_network_cards(user_id);
CREATE INDEX idx_ccoin_cards_domain ON ccoin_network_cards(str_domain);
CREATE INDEX idx_ccoin_cards_status ON ccoin_network_cards(status);
CREATE INDEX idx_ccoin_iban_currencies_card ON ccoin_internal_iban_currencies(card_id);
CREATE INDEX idx_ccoin_iban_currencies_currency ON ccoin_internal_iban_currencies(currency);
CREATE INDEX idx_ccoin_transactions_card ON ccoin_network_transactions(card_id);
CREATE INDEX idx_ccoin_transactions_status ON ccoin_network_transactions(status);

-- Enable RLS
ALTER TABLE ccoin_network_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE ccoin_internal_iban_currencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE ccoin_network_transactions ENABLE ROW LEVEL SECURITY;

-- RLS Policies for ccoin_network_cards
CREATE POLICY "Users can view their own CCoin network cards"
  ON ccoin_network_cards FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all CCoin network cards"
  ON ccoin_network_cards FOR SELECT
  USING (is_admin(auth.uid()));

CREATE POLICY "Admins can manage CCoin network cards"
  ON ccoin_network_cards FOR ALL
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- RLS Policies for ccoin_internal_iban_currencies
CREATE POLICY "Users can view their own magnet addresses"
  ON ccoin_internal_iban_currencies FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM ccoin_network_cards
    WHERE ccoin_network_cards.id = ccoin_internal_iban_currencies.card_id
    AND ccoin_network_cards.user_id = auth.uid()
  ));

CREATE POLICY "Admins can view all magnet addresses"
  ON ccoin_internal_iban_currencies FOR SELECT
  USING (is_admin(auth.uid()));

CREATE POLICY "Admins can manage magnet addresses"
  ON ccoin_internal_iban_currencies FOR ALL
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- RLS Policies for ccoin_network_transactions
CREATE POLICY "Users can view their own transactions"
  ON ccoin_network_transactions FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM ccoin_network_cards
    WHERE ccoin_network_cards.id = ccoin_network_transactions.card_id
    AND ccoin_network_cards.user_id = auth.uid()
  ));

CREATE POLICY "Admins can view all transactions"
  ON ccoin_network_transactions FOR SELECT
  USING (is_admin(auth.uid()));

CREATE POLICY "Admins can manage transactions"
  ON ccoin_network_transactions FOR ALL
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

CREATE POLICY "System can insert transactions"
  ON ccoin_network_transactions FOR INSERT
  WITH CHECK (true);

-- Function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_ccoin_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER update_ccoin_network_cards_updated_at
  BEFORE UPDATE ON ccoin_network_cards
  FOR EACH ROW EXECUTE FUNCTION update_ccoin_updated_at();

CREATE TRIGGER update_ccoin_iban_currencies_updated_at
  BEFORE UPDATE ON ccoin_internal_iban_currencies
  FOR EACH ROW EXECUTE FUNCTION update_ccoin_updated_at();