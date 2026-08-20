-- Add seller wallet address for ETH/BTC payments (private, not shown publicly)
ALTER TABLE public.domain_marketplace_listings
ADD COLUMN seller_wallet_address TEXT,
ADD COLUMN seller_wallet_currency TEXT;

-- Add escrow and workflow fields to transactions
ALTER TABLE public.domain_marketplace_transactions
ADD COLUMN escrow_status TEXT NOT NULL DEFAULT 'pending' CHECK (escrow_status IN ('pending', 'payment_received', 'admin_approved', 'released', 'disputed', 'refunded')),
ADD COLUMN payment_proof_url TEXT,
ADD COLUMN admin_notes TEXT,
ADD COLUMN admin_approved_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN admin_approved_by UUID REFERENCES auth.users(id),
ADD COLUMN released_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN buyer_wallet_address TEXT;

-- Add accepted_bid_id to track which bid was accepted
ALTER TABLE public.domain_marketplace_listings
ADD COLUMN accepted_bid_id UUID REFERENCES public.domain_marketplace_bids(id);

-- Add bid status for acceptance workflow
ALTER TABLE public.domain_marketplace_bids
ADD COLUMN status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'outbid', 'expired'));

-- Create index for escrow management
CREATE INDEX idx_transactions_escrow_status ON public.domain_marketplace_transactions(escrow_status);
CREATE INDEX idx_bids_status ON public.domain_marketplace_bids(status);