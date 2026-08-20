-- Insert the ExCcoinLp Investment Pool 2 data into wallet_pools table
INSERT INTO public.wallet_pools (
  user_id, 
  wallet_address, 
  pool_type, 
  balance
) VALUES (
  '00000000-0000-0000-0000-000000000001', -- System/global pool
  'ExCcoinLp-Pool-2-Global', 
  'CCoin', 
  246.11853
)
ON CONFLICT DO NOTHING;