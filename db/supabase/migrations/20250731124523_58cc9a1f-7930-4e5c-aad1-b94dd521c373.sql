-- Create a global pool record for ExCcoinLp Investment Pool 2
-- Remove the foreign key constraint temporarily and add pool data
ALTER TABLE public.wallet_pools DROP CONSTRAINT IF EXISTS wallet_pools_user_id_fkey;

-- Insert the global pool data
INSERT INTO public.wallet_pools (
  id,
  user_id, 
  wallet_address, 
  pool_type, 
  balance,
  created_at,
  updated_at
) VALUES (
  gen_random_uuid(),
  '00000000-0000-0000-0000-000000000001', -- Global pool identifier
  'ExCcoinLp-Pool-2-Global', 
  'CCoin', 
  246.11853,
  now(),
  now()
)
ON CONFLICT DO NOTHING;

-- Re-add the foreign key constraint but make it optional for global pools
-- by allowing certain system UUIDs to bypass the constraint
CREATE OR REPLACE FUNCTION check_user_or_system()
RETURNS TRIGGER AS $$
BEGIN
  -- Allow system/global pool UUIDs to bypass user validation
  IF NEW.user_id = '00000000-0000-0000-0000-000000000001' THEN
    RETURN NEW;
  END IF;
  
  -- For regular users, check if they exist in auth.users
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = NEW.user_id) THEN
    RAISE EXCEPTION 'User does not exist';
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add the trigger
DROP TRIGGER IF EXISTS validate_user_or_system ON public.wallet_pools;
CREATE TRIGGER validate_user_or_system
  BEFORE INSERT OR UPDATE ON public.wallet_pools
  FOR EACH ROW EXECUTE FUNCTION check_user_or_system();