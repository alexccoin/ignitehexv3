-- Create function to get aggregate staking pool statistics
CREATE OR REPLACE FUNCTION public.get_aggregate_staking_stats()
RETURNS TABLE(
  total_str_staked numeric,
  total_str_stakers bigint,
  total_ccos_staked numeric,
  total_ccos_stakers bigint,
  total_domain_staked numeric,
  total_domain_stakers bigint,
  total_domains_owned bigint,
  avg_str_apy numeric,
  avg_ccos_apy numeric,
  avg_domain_apy numeric
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    -- STR Pool Stats
    COALESCE(SUM(CASE WHEN pool_type = 'str' THEN staked_amount ELSE 0 END), 0) as total_str_staked,
    COUNT(CASE WHEN pool_type = 'str' AND staked_amount > 0 THEN user_id END) as total_str_stakers,
    
    -- CCOS Pool Stats
    COALESCE(SUM(CASE WHEN pool_type = 'ccos' THEN staked_amount ELSE 0 END), 0) as total_ccos_staked,
    COUNT(CASE WHEN pool_type = 'ccos' AND staked_amount > 0 THEN user_id END) as total_ccos_stakers,
    
    -- Domain Pool Stats
    COALESCE(SUM(CASE WHEN pool_type = 'domain' THEN staked_amount ELSE 0 END), 0) as total_domain_staked,
    COUNT(CASE WHEN pool_type = 'domain' AND staked_amount > 0 THEN user_id END) as total_domain_stakers,
    
    -- Domain Ownership Stats
    (SELECT COUNT(*) FROM user_profiles WHERE str_domain_owned IS NOT NULL AND str_domain_owned != '') as total_domains_owned,
    
    -- Average APY rates
    COALESCE(AVG(CASE WHEN pool_type = 'str' THEN apy_rate END), 0) as avg_str_apy,
    COALESCE(AVG(CASE WHEN pool_type = 'ccos' THEN apy_rate END), 0) as avg_ccos_apy,
    COALESCE(AVG(CASE WHEN pool_type = 'domain' THEN apy_rate END), 0) as avg_domain_apy
    
  FROM user_staking_pools;
END;
$function$;

-- Create function to get total portfolio value across all users
CREATE OR REPLACE FUNCTION public.get_total_ecosystem_value()
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  total_value numeric := 0;
  str_price numeric := 1.85; -- Default STR price, will be updated dynamically
  ccos_price numeric := 0.0021; -- Default CCOS price
BEGIN
  -- Calculate total value from all staking pools
  SELECT 
    COALESCE(SUM(
      CASE 
        WHEN pool_type = 'str' THEN (staked_amount + rewards_earned) * str_price
        WHEN pool_type = 'ccos' THEN (staked_amount + rewards_earned) * ccos_price
        WHEN pool_type = 'domain' THEN (staked_amount + rewards_earned) * str_price
        ELSE 0
      END
    ), 0)
  INTO total_value
  FROM user_staking_pools;
  
  RETURN total_value;
END;
$function$;

-- Allow public access to these functions
GRANT EXECUTE ON FUNCTION public.get_aggregate_staking_stats() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_total_ecosystem_value() TO anon, authenticated;