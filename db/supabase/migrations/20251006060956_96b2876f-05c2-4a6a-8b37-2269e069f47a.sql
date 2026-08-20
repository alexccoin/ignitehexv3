-- Improved resolve_str_address to support multiple sources and relaxed status checks
CREATE OR REPLACE FUNCTION public.resolve_str_address(p_address text)
 RETURNS TABLE(user_id uuid, full_address text, address_type text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid;
  v_full_address text;
  v_type text;
  v_addr text;
BEGIN
  v_addr := lower(trim(p_address));

  -- Handle STR domains like "str.something"
  IF v_addr LIKE 'str.%' THEN
    -- 1) Prefer records from str_domains, prioritizing minted/active/approved
    SELECT sd.user_id, sd.domain_name, 'str_domain'
      INTO v_user_id, v_full_address, v_type
    FROM str_domains sd
    WHERE lower(sd.domain_name) = v_addr
    ORDER BY CASE sd.status 
              WHEN 'minted' THEN 1 
              WHEN 'active' THEN 2 
              WHEN 'approved' THEN 3 
              ELSE 4 
            END
    LIMIT 1;

    IF v_user_id IS NOT NULL THEN
      RETURN QUERY SELECT v_user_id, v_full_address, v_type;
      RETURN;
    END IF;

    -- 2) Fallback to str_domain_connections mapping
    SELECT sdc.user_id, sdc.domain_name, 'str_domain_connection'
      INTO v_user_id, v_full_address, v_type
    FROM str_domain_connections sdc
    WHERE lower(sdc.domain_name) = v_addr
    LIMIT 1;

    IF v_user_id IS NOT NULL THEN
      RETURN QUERY SELECT v_user_id, v_full_address, v_type;
      RETURN;
    END IF;

    -- 3) Fallback to user_profile_connections.str_domain
    SELECT upc.user_id, upc.str_domain, 'profile_str_domain'
      INTO v_user_id, v_full_address, v_type
    FROM user_profile_connections upc
    WHERE lower(upc.str_domain) = v_addr
    LIMIT 1;

    IF v_user_id IS NOT NULL THEN
      RETURN QUERY SELECT v_user_id, v_full_address, v_type;
      RETURN;
    END IF;

  -- Handle direct STR wallet addresses
  ELSIF length(v_addr) >= 26 THEN
    SELECT up.user_id, up.str_wallet_address, 'str_wallet'
      INTO v_user_id, v_full_address, v_type
    FROM user_profiles up
    WHERE up.str_wallet_address = p_address
    LIMIT 1;

    IF v_user_id IS NOT NULL THEN
      RETURN QUERY SELECT v_user_id, v_full_address, v_type;
      RETURN;
    END IF;
  END IF;

  -- No match, return nothing
  RETURN;
END;
$function$;