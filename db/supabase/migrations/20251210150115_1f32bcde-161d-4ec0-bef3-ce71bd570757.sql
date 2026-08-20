-- Create domain_marketplace_listings table for buy now and auction listings
CREATE TABLE public.domain_marketplace_listings (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  domain_id UUID REFERENCES public.str_domains(id) ON DELETE CASCADE,
  seller_id UUID NOT NULL,
  domain_name TEXT NOT NULL,
  domain_type TEXT NOT NULL CHECK (domain_type IN ('standard', 'premium', 'business', 'brand')),
  listing_type TEXT NOT NULL CHECK (listing_type IN ('buy_now', 'auction', 'both')),
  buy_now_price NUMERIC,
  starting_bid NUMERIC,
  reserve_price NUMERIC,
  current_bid NUMERIC,
  current_bidder_id UUID,
  auction_end_at TIMESTAMP WITH TIME ZONE,
  description TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'sold', 'cancelled', 'expired')),
  views_count INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create domain_marketplace_bids table for auction bids
CREATE TABLE public.domain_marketplace_bids (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  listing_id UUID NOT NULL REFERENCES public.domain_marketplace_listings(id) ON DELETE CASCADE,
  bidder_id UUID NOT NULL,
  bid_amount NUMERIC NOT NULL,
  is_winning_bid BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create domain_marketplace_transactions for completed sales
CREATE TABLE public.domain_marketplace_transactions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  listing_id UUID REFERENCES public.domain_marketplace_listings(id),
  domain_id UUID REFERENCES public.str_domains(id),
  seller_id UUID NOT NULL,
  buyer_id UUID NOT NULL,
  sale_price NUMERIC NOT NULL,
  sale_type TEXT NOT NULL CHECK (sale_type IN ('buy_now', 'auction')),
  transaction_fee NUMERIC DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'cancelled', 'refunded')),
  completed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS on all tables
ALTER TABLE public.domain_marketplace_listings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.domain_marketplace_bids ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.domain_marketplace_transactions ENABLE ROW LEVEL SECURITY;

-- Policies for domain_marketplace_listings
CREATE POLICY "Anyone can view active listings" 
ON public.domain_marketplace_listings 
FOR SELECT 
USING (status = 'active' OR seller_id = auth.uid());

CREATE POLICY "Users can create their own listings" 
ON public.domain_marketplace_listings 
FOR INSERT 
WITH CHECK (auth.uid() = seller_id);

CREATE POLICY "Sellers can update their own listings" 
ON public.domain_marketplace_listings 
FOR UPDATE 
USING (auth.uid() = seller_id);

CREATE POLICY "Sellers can delete their own listings" 
ON public.domain_marketplace_listings 
FOR DELETE 
USING (auth.uid() = seller_id);

CREATE POLICY "Admins can manage all listings" 
ON public.domain_marketplace_listings 
FOR ALL 
USING (EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role = 'admin'));

-- Policies for domain_marketplace_bids
CREATE POLICY "Anyone can view bids on listings" 
ON public.domain_marketplace_bids 
FOR SELECT 
USING (true);

CREATE POLICY "Authenticated users can place bids" 
ON public.domain_marketplace_bids 
FOR INSERT 
WITH CHECK (auth.uid() = bidder_id AND auth.uid() IS NOT NULL);

CREATE POLICY "Admins can manage all bids" 
ON public.domain_marketplace_bids 
FOR ALL 
USING (EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role = 'admin'));

-- Policies for domain_marketplace_transactions
CREATE POLICY "Users can view their own transactions" 
ON public.domain_marketplace_transactions 
FOR SELECT 
USING (auth.uid() = seller_id OR auth.uid() = buyer_id);

CREATE POLICY "System can create transactions" 
ON public.domain_marketplace_transactions 
FOR INSERT 
WITH CHECK (true);

CREATE POLICY "Admins can manage all transactions" 
ON public.domain_marketplace_transactions 
FOR ALL 
USING (EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role = 'admin'));

-- Create indexes for better performance
CREATE INDEX idx_marketplace_listings_status ON public.domain_marketplace_listings(status);
CREATE INDEX idx_marketplace_listings_domain_type ON public.domain_marketplace_listings(domain_type);
CREATE INDEX idx_marketplace_listings_listing_type ON public.domain_marketplace_listings(listing_type);
CREATE INDEX idx_marketplace_listings_seller ON public.domain_marketplace_listings(seller_id);
CREATE INDEX idx_marketplace_bids_listing ON public.domain_marketplace_bids(listing_id);
CREATE INDEX idx_marketplace_transactions_buyer ON public.domain_marketplace_transactions(buyer_id);
CREATE INDEX idx_marketplace_transactions_seller ON public.domain_marketplace_transactions(seller_id);

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_marketplace_listing_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- Create trigger for automatic timestamp updates
CREATE TRIGGER update_marketplace_listing_timestamp
BEFORE UPDATE ON public.domain_marketplace_listings
FOR EACH ROW
EXECUTE FUNCTION public.update_marketplace_listing_updated_at();