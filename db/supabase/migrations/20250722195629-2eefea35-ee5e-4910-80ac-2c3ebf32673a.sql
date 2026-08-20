-- Add withdrawal functionality fields to founder_positions
ALTER TABLE founder_positions ADD COLUMN IF NOT EXISTS btc_wallet_locked boolean DEFAULT true;
ALTER TABLE founder_positions ADD COLUMN IF NOT EXISTS lock_start_date timestamp with time zone DEFAULT now();
ALTER TABLE founder_positions ADD COLUMN IF NOT EXISTS lock_end_date timestamp with time zone DEFAULT (now() + INTERVAL '90 days');
ALTER TABLE founder_positions ADD COLUMN IF NOT EXISTS withdrawal_executed boolean DEFAULT false;
ALTER TABLE founder_positions ADD COLUMN IF NOT EXISTS withdrawal_transaction_hash text;

-- Create withdrawal requests table
CREATE TABLE IF NOT EXISTS public.withdrawal_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  founder_position_id uuid NOT NULL REFERENCES founder_positions(id),
  withdrawal_address text NOT NULL,
  btc_amount numeric NOT NULL,
  usd_value_at_request numeric NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  requested_at timestamp with time zone NOT NULL DEFAULT now(),
  processed_at timestamp with time zone,
  transaction_hash text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Enable RLS on withdrawal_requests
ALTER TABLE public.withdrawal_requests ENABLE ROW LEVEL SECURITY;

-- Create policies for withdrawal_requests
CREATE POLICY "Users can view their own withdrawal requests" 
ON public.withdrawal_requests 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own withdrawal requests" 
ON public.withdrawal_requests 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own withdrawal requests" 
ON public.withdrawal_requests 
FOR UPDATE 
USING (auth.uid() = user_id);

-- Add updated_at trigger for withdrawal_requests
CREATE TRIGGER update_withdrawal_requests_updated_at
  BEFORE UPDATE ON public.withdrawal_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Function to check if withdrawal is available
CREATE OR REPLACE FUNCTION public.is_withdrawal_available(position_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  lock_end timestamp with time zone;
  wallet_locked boolean;
  withdrawal_done boolean;
BEGIN
  SELECT lock_end_date, btc_wallet_locked, withdrawal_executed
  INTO lock_end, wallet_locked, withdrawal_done
  FROM founder_positions 
  WHERE id = position_id;
  
  -- Check if withdrawal is available
  RETURN (
    lock_end IS NOT NULL AND 
    now() >= lock_end AND 
    wallet_locked = true AND 
    withdrawal_done = false
  );
END;
$$;