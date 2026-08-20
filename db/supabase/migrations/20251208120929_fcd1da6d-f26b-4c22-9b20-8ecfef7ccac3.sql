-- Create the missing merchant account for approved application
INSERT INTO public.merchant_accounts (
  user_id, 
  business_domain_id, 
  application_id, 
  merchant_id, 
  business_name, 
  payment_processing_enabled,
  status
) 
SELECT 
  user_id,
  business_domain_id,
  id,
  'MERCH_' || upper(substring(md5(random()::text) from 1 for 12)),
  business_name,
  COALESCE((requested_products->>'payment_processing')::boolean, false),
  'active'
FROM merchant_account_applications
WHERE status = 'approved'
AND id NOT IN (SELECT application_id FROM merchant_accounts WHERE application_id IS NOT NULL);