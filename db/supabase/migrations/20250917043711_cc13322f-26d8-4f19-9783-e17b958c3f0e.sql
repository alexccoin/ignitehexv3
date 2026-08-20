-- Create a function to get domain staking stats without requiring admin privileges
-- This function provides aggregate statistics that are safe for public consumption

CREATE OR REPLACE FUNCTION public.get_domain_staking_stats()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  total_stakers integer;
  total_staked numeric;
  total_rewards numeric;
  avg_apy numeric;
  result jsonb;
BEGIN
  -- Get aggregate domain staking statistics
  SELECT 
    COUNT(*) as stakers,
    COALESCE(SUM(staked_amount), 0) as staked,
    COALESCE(SUM(rewards_earned), 0) as rewards,
    COALESCE(AVG(apy_rate), 13.0) as apy
  INTO total_stakers, total_staked, total_rewards, avg_apy
  FROM user_staking_pools 
  WHERE pool_type = 'domain' 
    AND staked_amount > 0;

  result := jsonb_build_object(
    'total_stakers', total_stakers,
    'total_staked', total_staked,
    'total_rewards', total_rewards,
    'avg_apy', avg_apy,
    'updated_at', now()
  );
  
  RETURN result;
END;
$$;

-- Create a simplified domain staking view function for public access
CREATE OR REPLACE FUNCTION public.get_public_domain_staking_overview()
RETURNS TABLE(
  total_domain_stakers bigint,
  total_domain_staked numeric,
  total_domain_rewards numeric,
  average_domain_apy numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COUNT(*) as total_domain_stakers,
    COALESCE(SUM(usp.staked_amount), 0) as total_domain_staked,
    COALESCE(SUM(usp.rewards_earned), 0) as total_domain_rewards,
    COALESCE(AVG(usp.apy_rate), 13.0) as average_domain_apy
  FROM user_staking_pools usp
  WHERE usp.pool_type = 'domain' 
    AND usp.staked_amount > 0;
END;
$$;