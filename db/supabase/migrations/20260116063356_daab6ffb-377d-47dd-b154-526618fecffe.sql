-- Add wNFT shares column to user_str_shares
ALTER TABLE public.user_str_shares
ADD COLUMN IF NOT EXISTS wnft_shares numeric NOT NULL DEFAULT 0;