
-- Table for user stablecoin wallets (required to participate in marketplace)
CREATE TABLE public.marketplace_stablecoin_wallets (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  usdt_address TEXT,
  usdc_address TEXT,
  network TEXT NOT NULL DEFAULT 'ERC20',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT unique_user_stablecoin_wallet UNIQUE (user_id)
);

ALTER TABLE public.marketplace_stablecoin_wallets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own stablecoin wallets" ON public.marketplace_stablecoin_wallets
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own stablecoin wallets" ON public.marketplace_stablecoin_wallets
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own stablecoin wallets" ON public.marketplace_stablecoin_wallets
  FOR UPDATE USING (auth.uid() = user_id);

-- Table for token marketplace listings (STR, CCOS, ARSS + domains unified)
CREATE TABLE public.token_marketplace_listings (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  seller_id UUID NOT NULL,
  asset_type TEXT NOT NULL CHECK (asset_type IN ('token', 'domain')),
  asset_symbol TEXT NOT NULL, -- STR, CCOS, ARSS, or domain name for domains
  amount NUMERIC NOT NULL DEFAULT 0, -- token amount being sold (0 for domains)
  listing_type TEXT NOT NULL DEFAULT 'buy_now' CHECK (listing_type IN ('buy_now', 'auction', 'both')),
  price_per_unit NUMERIC, -- price per token in USD
  total_price NUMERIC, -- total asking price
  starting_bid NUMERIC,
  reserve_price NUMERIC,
  current_bid NUMERIC,
  current_bidder_id UUID,
  auction_end_at TIMESTAMP WITH TIME ZONE,
  description TEXT,
  seller_usdt_address TEXT,
  seller_usdc_address TEXT,
  domain_id UUID, -- reference for domain listings
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'sold', 'cancelled', 'expired', 'reserved')),
  views_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.token_marketplace_listings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view active token listings" ON public.token_marketplace_listings
  FOR SELECT USING (status = 'active' OR seller_id = auth.uid());
CREATE POLICY "Users can create own token listings" ON public.token_marketplace_listings
  FOR INSERT WITH CHECK (auth.uid() = seller_id);
CREATE POLICY "Users can update own token listings" ON public.token_marketplace_listings
  FOR UPDATE USING (auth.uid() = seller_id);

-- Table for escrowed/locked token balances
CREATE TABLE public.marketplace_escrow_balances (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  listing_id UUID NOT NULL REFERENCES public.token_marketplace_listings(id),
  asset_symbol TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  status TEXT NOT NULL DEFAULT 'locked' CHECK (status IN ('locked', 'released', 'transferred')),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  released_at TIMESTAMP WITH TIME ZONE
);

ALTER TABLE public.marketplace_escrow_balances ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own escrow balances" ON public.marketplace_escrow_balances
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can create own escrow entries" ON public.marketplace_escrow_balances
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own escrow entries" ON public.marketplace_escrow_balances
  FOR UPDATE USING (auth.uid() = user_id);

-- Indexes
CREATE INDEX idx_token_listings_status ON public.token_marketplace_listings(status);
CREATE INDEX idx_token_listings_seller ON public.token_marketplace_listings(seller_id);
CREATE INDEX idx_token_listings_asset ON public.token_marketplace_listings(asset_type, asset_symbol);
CREATE INDEX idx_escrow_user ON public.marketplace_escrow_balances(user_id);
CREATE INDEX idx_escrow_listing ON public.marketplace_escrow_balances(listing_id);
