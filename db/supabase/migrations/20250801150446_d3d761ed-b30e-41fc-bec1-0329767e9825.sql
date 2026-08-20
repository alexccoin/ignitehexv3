-- Create individual user staking pools
CREATE TABLE IF NOT EXISTS user_staking_pools (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  pool_type text NOT NULL CHECK (pool_type IN ('str', 'ccos', 'domain')),
  balance numeric DEFAULT 0,
  staked_amount numeric DEFAULT 0,
  rewards_earned numeric DEFAULT 0,
  apy_rate numeric DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  UNIQUE(user_id, pool_type)
);

-- Create staking requests table for admin approval
CREATE TABLE IF NOT EXISTS staking_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  pool_type text NOT NULL CHECK (pool_type IN ('str', 'ccos', 'domain')),
  request_type text NOT NULL CHECK (request_type IN ('stake', 'unstake')),
  amount numeric NOT NULL,
  domain_name text, -- For domain staking only
  description text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  admin_notes text,
  approved_by uuid,
  requested_at timestamp with time zone DEFAULT now(),
  processed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

-- Enable RLS on both tables
ALTER TABLE user_staking_pools ENABLE ROW LEVEL SECURITY;
ALTER TABLE staking_requests ENABLE ROW LEVEL SECURITY;

-- RLS policies for user_staking_pools
CREATE POLICY "Users can view their own staking pools" 
ON user_staking_pools 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own staking pools" 
ON user_staking_pools 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own staking pools" 
ON user_staking_pools 
FOR UPDATE 
USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all staking pools" 
ON user_staking_pools 
FOR ALL 
USING (is_admin(auth.uid()));

-- RLS policies for staking_requests
CREATE POLICY "Users can view their own staking requests" 
ON staking_requests 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can create staking requests" 
ON staking_requests 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view all staking requests" 
ON staking_requests 
FOR ALL 
USING (is_admin(auth.uid()));

-- Function to initialize user staking pools
CREATE OR REPLACE FUNCTION initialize_user_staking_pools(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Insert default pools for STR, CCOS, and Domain if they don't exist
  INSERT INTO user_staking_pools (user_id, pool_type, balance, apy_rate)
  VALUES 
    (target_user_id, 'str', 0, 12.5),
    (target_user_id, 'ccos', 0, 15.0),
    (target_user_id, 'domain', 0, 8.0)
  ON CONFLICT (user_id, pool_type) DO NOTHING;
END;
$$;

-- Function to process staking request (admin only)
CREATE OR REPLACE FUNCTION process_staking_request(
  request_id uuid,
  approve boolean,
  admin_notes text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  request_data staking_requests%ROWTYPE;
BEGIN
  -- Check if the requesting user is admin
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  -- Get the request data
  SELECT * INTO request_data 
  FROM staking_requests 
  WHERE id = request_id AND status = 'pending';

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  -- Update request status
  UPDATE staking_requests 
  SET 
    status = CASE WHEN approve THEN 'approved' ELSE 'rejected' END,
    admin_notes = process_staking_request.admin_notes,
    approved_by = auth.uid(),
    processed_at = now(),
    updated_at = now()
  WHERE id = request_id;

  -- If approved, update the user's staking pool
  IF approve THEN
    -- Ensure user has staking pools initialized
    PERFORM initialize_user_staking_pools(request_data.user_id);
    
    -- Update the pool balance
    IF request_data.request_type = 'stake' THEN
      UPDATE user_staking_pools 
      SET 
        balance = balance + request_data.amount,
        staked_amount = staked_amount + request_data.amount,
        updated_at = now()
      WHERE user_id = request_data.user_id AND pool_type = request_data.pool_type;
    ELSIF request_data.request_type = 'unstake' THEN
      UPDATE user_staking_pools 
      SET 
        balance = GREATEST(0, balance - request_data.amount),
        staked_amount = GREATEST(0, staked_amount - request_data.amount),
        updated_at = now()
      WHERE user_id = request_data.user_id AND pool_type = request_data.pool_type;
    END IF;
  END IF;

  RETURN TRUE;
END;
$$;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_user_staking_pools_user_id ON user_staking_pools(user_id);
CREATE INDEX IF NOT EXISTS idx_user_staking_pools_pool_type ON user_staking_pools(pool_type);
CREATE INDEX IF NOT EXISTS idx_staking_requests_user_id ON staking_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_staking_requests_status ON staking_requests(status);

-- Add trigger to automatically create staking pools when user profile is created
CREATE OR REPLACE FUNCTION auto_create_staking_pools()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  PERFORM initialize_user_staking_pools(NEW.user_id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_auto_create_staking_pools
  AFTER INSERT ON user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION auto_create_staking_pools();