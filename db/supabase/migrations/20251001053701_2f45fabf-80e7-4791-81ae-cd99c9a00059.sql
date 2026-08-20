-- Create VIP users tracking table
CREATE TABLE IF NOT EXISTS vip_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  vip_status text NOT NULL DEFAULT 'active',
  qualification_type text NOT NULL, -- 'str_holder', 'domain_holder', 'both'
  total_str_staked numeric DEFAULT 0,
  total_domains_staked numeric DEFAULT 0,
  qualified_at timestamp with time zone DEFAULT now(),
  last_checked timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  UNIQUE(user_id)
);

-- Enable RLS
ALTER TABLE vip_users ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Admins can view all VIP users"
  ON vip_users FOR SELECT
  TO authenticated
  USING (is_admin(auth.uid()));

CREATE POLICY "Admins can manage VIP users"
  ON vip_users FOR ALL
  TO authenticated
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- Function to update VIP status for all qualifying users
CREATE OR REPLACE FUNCTION update_vip_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_record RECORD;
  vip_count INTEGER := 0;
  new_vips INTEGER := 0;
  removed_vips INTEGER := 0;
BEGIN
  -- Find all users with qualifying staking amounts
  FOR user_record IN
    SELECT 
      usp.user_id,
      SUM(CASE WHEN usp.pool_type = 'str' THEN usp.staked_amount ELSE 0 END) as total_str,
      SUM(CASE WHEN usp.pool_type = 'domain' THEN usp.staked_amount ELSE 0 END) as total_domains
    FROM user_staking_pools usp
    GROUP BY usp.user_id
    HAVING 
      SUM(CASE WHEN usp.pool_type = 'str' THEN usp.staked_amount ELSE 0 END) >= 10000000
      OR SUM(CASE WHEN usp.pool_type = 'domain' THEN usp.staked_amount ELSE 0 END) >= 1000
  LOOP
    -- Determine qualification type
    DECLARE
      qual_type text;
    BEGIN
      IF user_record.total_str >= 10000000 AND user_record.total_domains >= 1000 THEN
        qual_type := 'both';
      ELSIF user_record.total_str >= 10000000 THEN
        qual_type := 'str_holder';
      ELSE
        qual_type := 'domain_holder';
      END IF;

      -- Insert or update VIP status
      INSERT INTO vip_users (
        user_id, 
        qualification_type, 
        total_str_staked, 
        total_domains_staked,
        vip_status,
        last_checked
      ) VALUES (
        user_record.user_id,
        qual_type,
        user_record.total_str,
        user_record.total_domains,
        'active',
        now()
      )
      ON CONFLICT (user_id) 
      DO UPDATE SET
        qualification_type = EXCLUDED.qualification_type,
        total_str_staked = EXCLUDED.total_str_staked,
        total_domains_staked = EXCLUDED.total_domains_staked,
        vip_status = 'active',
        last_checked = now(),
        updated_at = now();

      vip_count := vip_count + 1;
      
      -- Check if this is a new VIP
      IF NOT EXISTS (
        SELECT 1 FROM vip_users 
        WHERE user_id = user_record.user_id 
        AND qualified_at < now() - interval '1 minute'
      ) THEN
        new_vips := new_vips + 1;
      END IF;
    END;
  END LOOP;

  -- Mark users who no longer qualify as inactive
  UPDATE vip_users
  SET vip_status = 'inactive', updated_at = now()
  WHERE user_id NOT IN (
    SELECT user_id FROM user_staking_pools
    GROUP BY user_id
    HAVING 
      SUM(CASE WHEN pool_type = 'str' THEN staked_amount ELSE 0 END) >= 10000000
      OR SUM(CASE WHEN pool_type = 'domain' THEN staked_amount ELSE 0 END) >= 1000
  ) AND vip_status = 'active';

  GET DIAGNOSTICS removed_vips = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', true,
    'total_vips', vip_count,
    'new_vips', new_vips,
    'removed_vips', removed_vips,
    'timestamp', now()
  );
END;
$$;

-- Create a view for easy VIP user lookup with profile info
CREATE OR REPLACE VIEW vip_users_detailed AS
SELECT 
  v.id,
  v.user_id,
  v.vip_status,
  v.qualification_type,
  v.total_str_staked,
  v.total_domains_staked,
  v.qualified_at,
  v.last_checked,
  up.full_name,
  up.email_address,
  up.str_domain_username
FROM vip_users v
LEFT JOIN user_profiles up ON v.user_id = up.user_id
WHERE v.vip_status = 'active'
ORDER BY v.total_str_staked DESC, v.total_domains_staked DESC;

-- Run initial VIP status update
SELECT update_vip_status();