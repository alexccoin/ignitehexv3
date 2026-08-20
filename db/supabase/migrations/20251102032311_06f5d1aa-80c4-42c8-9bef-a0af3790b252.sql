-- Add status column to user_staking_pools for managing declined positions
ALTER TABLE user_staking_pools
ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active';

-- Add check constraint for status values
ALTER TABLE user_staking_pools
ADD CONSTRAINT user_staking_pools_status_check 
CHECK (status IN ('active', 'declined', 'suspended'));

-- Add index for efficient filtering
CREATE INDEX IF NOT EXISTS idx_user_staking_pools_status 
ON user_staking_pools(status);

-- Add admin_notes column for tracking reasons
ALTER TABLE user_staking_pools
ADD COLUMN IF NOT EXISTS admin_notes text;

-- Add declined_at timestamp
ALTER TABLE user_staking_pools
ADD COLUMN IF NOT EXISTS declined_at timestamp with time zone;

-- Add declined_by to track admin who declined
ALTER TABLE user_staking_pools
ADD COLUMN IF NOT EXISTS declined_by uuid REFERENCES auth.users(id);