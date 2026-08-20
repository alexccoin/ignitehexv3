-- Fix the SECURITY DEFINER view issue by recreating with SECURITY INVOKER
DROP VIEW IF EXISTS public.public_product_catalog;

CREATE VIEW public.public_product_catalog 
WITH (security_invoker = true)
AS
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

-- Add a policy to allow authenticated users to select from the underlying table via the view
-- This is needed because with security_invoker, the querying user's permissions are used
CREATE POLICY "Authenticated users can view active products via view" ON public.merchant_products
  FOR SELECT USING (is_active = true AND auth.role() = 'authenticated');