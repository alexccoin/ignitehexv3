-- Create voucher redemptions table
CREATE TABLE public.voucher_redemptions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  token_type TEXT NOT NULL CHECK (token_type IN ('str', 'ccos', 'arss')),
  str_dome_username TEXT NOT NULL,
  str_dome_email TEXT NOT NULL,
  full_name TEXT NOT NULL,
  email_address TEXT NOT NULL,
  package_type TEXT NOT NULL,
  deposit_address TEXT NOT NULL,
  payment_type TEXT NOT NULL CHECK (payment_type IN ('crypto', 'bank')),
  payment_hash TEXT,
  proof_of_payment_url TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'approved', 'rejected')),
  admin_notes TEXT,
  processed_by UUID,
  processed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.voucher_redemptions ENABLE ROW LEVEL SECURITY;

-- Create policies for voucher redemptions
CREATE POLICY "Users can insert their own voucher redemptions"
ON public.voucher_redemptions
FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view their own voucher redemptions"
ON public.voucher_redemptions
FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own pending voucher redemptions"
ON public.voucher_redemptions
FOR UPDATE
USING (auth.uid() = user_id AND status = 'pending')
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view all voucher redemptions"
ON public.voucher_redemptions
FOR SELECT
USING (is_admin(auth.uid()));

CREATE POLICY "Admins can update all voucher redemptions"
ON public.voucher_redemptions
FOR UPDATE
USING (is_admin(auth.uid()));

-- Create storage bucket for voucher proofs
INSERT INTO storage.buckets (id, name, public) 
VALUES ('voucher-proofs', 'voucher-proofs', false)
ON CONFLICT (id) DO NOTHING;

-- Create storage policies for voucher proofs
CREATE POLICY "Users can upload their own voucher proofs"
ON storage.objects
FOR INSERT
WITH CHECK (bucket_id = 'voucher-proofs' AND auth.uid()::text = (storage.foldername(name))[1]);

CREATE POLICY "Users can view their own voucher proofs"
ON storage.objects
FOR SELECT
USING (bucket_id = 'voucher-proofs' AND auth.uid()::text = (storage.foldername(name))[1]);

CREATE POLICY "Admins can view all voucher proofs"
ON storage.objects
FOR SELECT
USING (bucket_id = 'voucher-proofs' AND is_admin(auth.uid()));

-- Create index for better performance
CREATE INDEX idx_voucher_redemptions_user_id ON public.voucher_redemptions(user_id);
CREATE INDEX idx_voucher_redemptions_status ON public.voucher_redemptions(status);
CREATE INDEX idx_voucher_redemptions_token_type ON public.voucher_redemptions(token_type);