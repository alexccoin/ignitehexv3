-- Update STR pool APY rate from 9.3% to 11%
UPDATE user_staking_pools 
SET apy_rate = 11.0
WHERE pool_type = 'str';

-- Update the initialize function with new STR APY rate
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
    (target_user_id, 'str', 0, 11.0),
    (target_user_id, 'ccos', 0, 12.5),
    (target_user_id, 'domain', 0, 13.0)
  ON CONFLICT (user_id, pool_type) DO NOTHING;
END;
$function$;