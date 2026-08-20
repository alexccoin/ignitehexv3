-- SECURITY FIX 1: Restrict merchant_products public access
-- Drop the overly permissive policy and create a more restrictive one

DROP POLICY IF EXISTS "Users can view active products" ON public.merchant_products;

-- Create a policy that allows:
-- 1. Merchants to see their own products (all fields)
-- 2. Authenticated users can only see limited product info for browsing
CREATE POLICY "Merchants can view their own products" ON public.merchant_products
  FOR SELECT USING (auth.uid() = user_id);

-- Create a secure view for public product browsing (no sensitive merchant/user info)
CREATE OR REPLACE VIEW public.public_product_catalog AS
SELECT 
  id,
  product_name,
  description,
  price,
  price_currency,
  crypto_price,
  crypto_currency,
  category,
  image_url,
  is_digital,
  created_at
FROM public.merchant_products
WHERE is_active = true;

-- Grant access to the view for authenticated users
GRANT SELECT ON public.public_product_catalog TO authenticated;

-- SECURITY FIX 2: Create API access audit log table
CREATE TABLE IF NOT EXISTS public.api_access_logs (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  api_key_hash TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  method TEXT NOT NULL,
  ip_address INET,
  user_agent TEXT,
  request_params JSONB,
  response_status INTEGER,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS on audit logs - only admins can read
ALTER TABLE public.api_access_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Only admins can view API logs" ON public.api_access_logs
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role = 'admin')
  );

-- Create rate limiting table
CREATE TABLE IF NOT EXISTS public.api_rate_limits (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  api_key_hash TEXT NOT NULL,
  ip_address INET,
  request_count INTEGER NOT NULL DEFAULT 1,
  window_start TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_api_rate_limits_key_window ON public.api_rate_limits(api_key_hash, window_start);
CREATE INDEX IF NOT EXISTS idx_api_access_logs_created ON public.api_access_logs(created_at);

-- Enable RLS
ALTER TABLE public.api_rate_limits ENABLE ROW LEVEL SECURITY;

-- Only allow edge functions (service role) to manage rate limits
CREATE POLICY "Service role manages rate limits" ON public.api_rate_limits
  FOR ALL USING (false);

-- SECURITY FIX 3: Update encryption tracking without breaking existing data
-- Add columns to track encryption status properly
-- The actual encryption happens at application layer before storage

-- Add encryption metadata columns if they don't exist
DO $$
BEGIN
  -- Add encryption_version to track which encryption algorithm was used
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'user_profiles' AND column_name = 'encryption_version') THEN
    ALTER TABLE public.user_profiles ADD COLUMN encryption_version INTEGER DEFAULT 0;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'iban_accounts' AND column_name = 'encryption_version') THEN
    ALTER TABLE public.iban_accounts ADD COLUMN encryption_version INTEGER DEFAULT 0;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'github_integrations' AND column_name = 'encryption_version') THEN
    ALTER TABLE public.github_integrations ADD COLUMN encryption_version INTEGER DEFAULT 0;
  END IF;
END $$;

-- Create a secure function to mark data as encrypted (called after client-side encryption)
CREATE OR REPLACE FUNCTION mark_data_encrypted(
  p_table_name TEXT,
  p_record_id UUID,
  p_encrypted_data TEXT,
  p_field_name TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Validate table name to prevent SQL injection
  IF p_table_name NOT IN ('user_profiles', 'iban_accounts', 'github_integrations') THEN
    RAISE EXCEPTION 'Invalid table name';
  END IF;
  
  -- Validate field name
  IF p_table_name = 'user_profiles' AND p_field_name NOT IN ('wallet_recovery_words') THEN
    RAISE EXCEPTION 'Invalid field name for user_profiles';
  END IF;
  
  IF p_table_name = 'iban_accounts' AND p_field_name NOT IN ('iban', 'bic') THEN
    RAISE EXCEPTION 'Invalid field name for iban_accounts';
  END IF;
  
  IF p_table_name = 'github_integrations' AND p_field_name NOT IN ('access_token') THEN
    RAISE EXCEPTION 'Invalid field name for github_integrations';
  END IF;
  
  -- Update the record with encrypted data
  IF p_table_name = 'user_profiles' THEN
    UPDATE user_profiles 
    SET wallet_recovery_words = p_encrypted_data,
        recovery_words_encrypted = true,
        encryption_version = 1,
        updated_at = now()
    WHERE id = p_record_id;
  ELSIF p_table_name = 'iban_accounts' THEN
    IF p_field_name = 'iban' THEN
      UPDATE iban_accounts 
      SET iban = p_encrypted_data,
          is_data_encrypted = true,
          encryption_version = 1,
          updated_at = now()
      WHERE id = p_record_id;
    ELSIF p_field_name = 'bic' THEN
      UPDATE iban_accounts 
      SET bic = p_encrypted_data,
          encryption_version = 1,
          updated_at = now()
      WHERE id = p_record_id;
    END IF;
  ELSIF p_table_name = 'github_integrations' THEN
    UPDATE github_integrations 
    SET access_token = p_encrypted_data,
        is_token_encrypted = true,
        encryption_version = 1,
        updated_at = now()
    WHERE id = p_record_id;
  END IF;
  
  RETURN true;
END;
$$;

-- Create security event logging
CREATE TABLE IF NOT EXISTS public.security_events (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  event_type TEXT NOT NULL,
  severity TEXT NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  user_id UUID,
  ip_address INET,
  details JSONB,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.security_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Only admins can view security events" ON public.security_events
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role = 'admin')
  );

CREATE INDEX IF NOT EXISTS idx_security_events_type ON public.security_events(event_type);
CREATE INDEX IF NOT EXISTS idx_security_events_created ON public.security_events(created_at);