-- Fix security definer view by enabling security invoker mode
CREATE OR REPLACE VIEW public.starw_purchases_comprehensive 
WITH (security_invoker=on) 
AS
SELECT 
  sp.*,
  up.full_name as processed_by_name,
  up.email_address as processed_by_email,
  user_up.str_wallet_address as customer_wallet,
  user_up.bsc_wallet_address as customer_bsc_wallet,
  (
    SELECT COUNT(*) 
    FROM starw_interaction_history 
    WHERE starw_purchase_id = sp.id
  ) as interaction_count,
  (
    SELECT json_agg(
      json_build_object(
        'action_type', action_type,
        'action_description', action_description,
        'created_at', created_at,
        'performed_by', performed_by
      ) ORDER BY created_at DESC
    )
    FROM starw_interaction_history 
    WHERE starw_purchase_id = sp.id
  ) as interaction_history
FROM public.starw_purchases sp
LEFT JOIN public.user_profiles up ON sp.processed_by = up.user_id
LEFT JOIN public.user_profiles user_up ON sp.user_id = user_up.user_id;