-- Fix resolve_str_address to remove non-existent column reference (sd.is_active)
CREATE OR REPLACE FUNCTION public.resolve_str_address(p_address text)
 RETURNS TABLE(user_id uuid, full_address text, address_type text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Check if it's a str.name domain
  IF p_address LIKE 'str.%' THEN
    RETURN QUERY
    SELECT 
      sd.user_id,
      sd.domain_name as full_address,
      'str_domain' as address_type
    FROM str_domains sd
    WHERE sd.domain_name = p_address 
      AND sd.status = 'minted'
    LIMIT 1;
  -- Check if it's a STR wallet address
  ELSIF LENGTH(p_address) >= 26 THEN
    RETURN QUERY
    SELECT 
      up.user_id,
      up.str_wallet_address as full_address,
      'str_wallet' as address_type
    FROM user_profiles up
    WHERE up.str_wallet_address = p_address
    LIMIT 1;
  END IF;
END;
$function$;