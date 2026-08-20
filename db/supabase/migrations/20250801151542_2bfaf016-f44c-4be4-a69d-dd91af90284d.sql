-- Update default APY rates for staking pools
UPDATE user_staking_pools 
SET apy_rate = CASE 
  WHEN pool_type = 'str' THEN 9.3
  WHEN pool_type = 'ccos' THEN 12.5  
  WHEN pool_type = 'domain' THEN 13.0
  ELSE apy_rate
END;

-- Update the initialize function with new APY rates
CREATE OR REPLACE FUNCTION public.initialize_user_staking_pools(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Insert default pools for STR, CCOS, and Domain if they don't exist
  INSERT INTO user_staking_pools (user_id, pool_type, balance, apy_rate)
  VALUES 
    (target_user_id, 'str', 0, 9.3),
    (target_user_id, 'ccos', 0, 12.5),
    (target_user_id, 'domain', 0, 13.0)
  ON CONFLICT (user_id, pool_type) DO NOTHING;
END;
$function$;