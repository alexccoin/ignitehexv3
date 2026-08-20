-- Drop the problematic security definer view
DROP VIEW IF EXISTS founder_position_details;

-- Create a function to get founder position details instead
CREATE OR REPLACE FUNCTION public.get_founder_position_details(link_id uuid)
RETURNS TABLE (
  id uuid,
  user_id uuid,
  unique_link_id uuid,
  position_number integer,
  title text,
  input_btc_amount numeric,
  output_btc_amount numeric,
  current_usd_value numeric,
  expected_btc_return numeric,
  ccos_mint_percentage numeric,
  withdrawal_address text,
  deposit_date timestamp with time zone,
  withdrawal_available_date timestamp with time zone,
  status text,
  is_prime boolean,
  position_type text,
  btc_wallet_locked boolean,
  lock_end_date timestamp with time zone,
  withdrawal_executed boolean,
  is_withdrawal_ready boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    fp.id,
    fp.user_id,
    fp.unique_link_id,
    fp.position_number,
    fp.title,
    fp.input_btc_amount,
    fp.output_btc_amount,
    fp.current_usd_value,
    fp.expected_btc_return,
    fp.ccos_mint_percentage,
    fp.withdrawal_address,
    fp.deposit_date,
    fp.withdrawal_available_date,
    fp.status,
    fp.is_prime,
    fp.position_type,
    fp.btc_wallet_locked,
    fp.lock_end_date,
    fp.withdrawal_executed,
    CASE 
      WHEN fp.lock_end_date <= now() AND fp.btc_wallet_locked = true AND fp.withdrawal_executed = false THEN true
      ELSE false
    END as is_withdrawal_ready
  FROM founder_positions fp
  WHERE fp.unique_link_id = link_id;
END;
$$;