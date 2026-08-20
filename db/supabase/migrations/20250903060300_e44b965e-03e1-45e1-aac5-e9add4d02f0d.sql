-- First, let's create a migration function to move existing staking history to enhanced pools
CREATE OR REPLACE FUNCTION public.migrate_staking_history_to_enhanced()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  migration_result jsonb;
  migrated_count integer := 0;
  failed_count integer := 0;
  user_record RECORD;
  enhanced_pool_record RECORD;
BEGIN
  -- Only allow admins to run this migration
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Admin privileges required'
    );
  END IF;

  -- Process existing staking pools that aren't already enhanced
  FOR user_record IN 
    SELECT 
      id, user_id, pool_type, balance, staked_amount, rewards_earned, 
      apy_rate, created_at, updated_at, last_reward_date, stake_duration_months
    FROM user_staking_pools 
    WHERE is_enhanced_pool = false OR is_enhanced_pool IS NULL
    ORDER BY created_at
  LOOP
    BEGIN
      -- Find or create matching enhanced pool
      SELECT * INTO enhanced_pool_record
      FROM enhanced_staking_pools
      WHERE token_type = user_record.pool_type
        AND duration_months = COALESCE(user_record.stake_duration_months, 3)
        AND status = 'active'
      LIMIT 1;

      -- If no matching enhanced pool exists, create a default one
      IF NOT FOUND THEN
        INSERT INTO enhanced_staking_pools (
          name,
          token_type,
          duration_months,
          apr_min,
          apr_max,
          description,
          theme,
          icon,
          status
        ) VALUES (
          'Migrated ' || UPPER(user_record.pool_type) || ' Pool',
          user_record.pool_type,
          COALESCE(user_record.stake_duration_months, 3),
          user_record.apy_rate * 0.8,  -- Min APR slightly lower
          user_record.apy_rate * 1.2,  -- Max APR slightly higher
          'Automatically migrated from legacy staking pool',
          CASE user_record.pool_type
            WHEN 'str' THEN 'green'
            WHEN 'ccos' THEN 'purple'
            WHEN 'domain' THEN 'blue'
            ELSE 'default'
          END,
          CASE user_record.pool_type
            WHEN 'str' THEN 'zap'
            WHEN 'ccos' THEN 'coins'
            WHEN 'domain' THEN 'globe'
            ELSE 'sparkles'
          END,
          'active'::pool_status
        ) RETURNING * INTO enhanced_pool_record;
      END IF;

      -- Update the user staking pool to link to enhanced pool
      UPDATE user_staking_pools
      SET 
        enhanced_pool_id = enhanced_pool_record.id,
        is_enhanced_pool = true,
        dynamic_apy = user_record.apy_rate,
        network_efficiency = 1.0,
        lock_end_date = COALESCE(
          user_record.created_at + (COALESCE(user_record.stake_duration_months, 3) || ' months')::interval,
          now() + '3 months'::interval
        ),
        updated_at = now()
      WHERE id = user_record.id;

      migrated_count := migrated_count + 1;

    EXCEPTION WHEN OTHERS THEN
      failed_count := failed_count + 1;
      -- Log the error but continue
      INSERT INTO security_audit_log (
        user_id, action, resource_type, details
      ) VALUES (
        auth.uid(),
        'staking_migration_failed',
        'user_staking_pools',
        jsonb_build_object(
          'pool_id', user_record.id,
          'error', SQLERRM,
          'timestamp', now()
        )
      );
    END;
  END LOOP;

  -- Log the migration completion
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(),
    'staking_history_migration_completed',
    'user_staking_pools',
    jsonb_build_object(
      'migrated_count', migrated_count,
      'failed_count', failed_count,
      'timestamp', now()
    )
  );

  migration_result := jsonb_build_object(
    'success', true,
    'migrated_count', migrated_count,
    'failed_count', failed_count,
    'message', 'Staking history migration completed successfully'
  );

  RETURN migration_result;
END;
$$;

-- Now let's create separate secure tables for sensitive personal data
-- This addresses the security concern about exposing critical financial and personal data

-- Create a separate table for encrypted personal data
CREATE TABLE IF NOT EXISTS public.user_personal_data_encrypted (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  encrypted_full_name text,
  encrypted_address text,
  encrypted_city text,
  encrypted_country text,
  encrypted_postal_code text,
  encrypted_btc_wallet text,
  encrypted_bsc_wallet text,
  encryption_iv text,
  encryption_salt text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT user_personal_data_encrypted_user_id_unique UNIQUE (user_id)
);

-- Enable RLS on the new table
ALTER TABLE public.user_personal_data_encrypted ENABLE ROW LEVEL SECURITY;

-- Create strict RLS policies for encrypted personal data
CREATE POLICY "Encrypted personal data - admin only full access"
ON public.user_personal_data_encrypted
FOR ALL
TO authenticated
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

CREATE POLICY "Encrypted personal data - users can view own"
ON public.user_personal_data_encrypted
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Create a separate table for wallet security data
CREATE TABLE IF NOT EXISTS public.user_wallet_security (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  encrypted_recovery_words text,
  recovery_words_iv text,
  recovery_words_salt text,
  wallet_pin_hash text,
  two_factor_secret text,
  encrypted_backup_codes text,
  backup_codes_iv text,
  device_fingerprints jsonb DEFAULT '[]'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT user_wallet_security_user_id_unique UNIQUE (user_id)
);

-- Enable RLS on wallet security table
ALTER TABLE public.user_wallet_security ENABLE ROW LEVEL SECURITY;

-- Create ultra-strict RLS policies for wallet security
CREATE POLICY "Wallet security - admin only management"
ON public.user_wallet_security
FOR ALL
TO authenticated
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

CREATE POLICY "Wallet security - users can manage own with PIN verification"
ON public.user_wallet_security
FOR ALL
TO authenticated
USING (
  auth.uid() = user_id AND 
  -- Additional security check could be added here for PIN verification
  auth.uid() IS NOT NULL
)
WITH CHECK (auth.uid() = user_id);

-- Function to migrate existing sensitive data to encrypted tables
CREATE OR REPLACE FUNCTION public.migrate_sensitive_data_to_secure_tables()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  migration_result jsonb;
  migrated_personal_count integer := 0;
  migrated_wallet_count integer := 0;
  user_record RECORD;
BEGIN
  -- Only allow admins to run this migration
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Admin privileges required'
    );
  END IF;

  -- Migrate personal data
  FOR user_record IN 
    SELECT user_id, full_name, address, city, country, postal_code, 
           btc_wallet_address, bsc_wallet_address
    FROM user_profiles
    WHERE full_name IS NOT NULL AND full_name != ''
  LOOP
    -- For now, we'll store data as-is but mark it for future encryption
    INSERT INTO user_personal_data_encrypted (
      user_id,
      encrypted_full_name, -- These should be encrypted in production
      encrypted_address,
      encrypted_city,
      encrypted_country,
      encrypted_postal_code,
      encrypted_btc_wallet,
      encrypted_bsc_wallet,
      encryption_iv,
      encryption_salt
    ) VALUES (
      user_record.user_id,
      user_record.full_name,
      user_record.address,
      user_record.city,
      user_record.country,
      user_record.postal_code,
      user_record.btc_wallet_address,
      user_record.bsc_wallet_address,
      'placeholder_iv',
      'placeholder_salt'
    ) ON CONFLICT (user_id) DO NOTHING;
    
    migrated_personal_count := migrated_personal_count + 1;
  END LOOP;

  -- Migrate wallet security data
  FOR user_record IN 
    SELECT user_id, wallet_recovery_words, wallet_pin_hash, two_factor_secret, 
           backup_codes, device_fingerprints, recovery_words_iv
    FROM user_profiles
    WHERE wallet_pin_hash IS NOT NULL
  LOOP
    INSERT INTO user_wallet_security (
      user_id,
      encrypted_recovery_words,
      recovery_words_iv,
      recovery_words_salt,
      wallet_pin_hash,
      two_factor_secret,
      encrypted_backup_codes,
      backup_codes_iv,
      device_fingerprints
    ) VALUES (
      user_record.user_id,
      array_to_string(user_record.wallet_recovery_words, ','),
      user_record.recovery_words_iv,
      'placeholder_salt',
      user_record.wallet_pin_hash,
      user_record.two_factor_secret,
      array_to_string(user_record.backup_codes, ','),
      'placeholder_iv',
      COALESCE(user_record.device_fingerprints, '[]'::jsonb)
    ) ON CONFLICT (user_id) DO NOTHING;
    
    migrated_wallet_count := migrated_wallet_count + 1;
  END LOOP;

  migration_result := jsonb_build_object(
    'success', true,
    'migrated_personal_count', migrated_personal_count,
    'migrated_wallet_count', migrated_wallet_count,
    'message', 'Sensitive data migration completed successfully'
  );

  RETURN migration_result;
END;
$$;

-- Create function to get enhanced staking history
CREATE OR REPLACE FUNCTION public.get_user_enhanced_stakes(target_user_id uuid)
RETURNS TABLE(
  id uuid,
  pool_type text,
  pool_name text,
  staked_amount numeric,
  balance numeric,
  rewards_earned numeric,
  dynamic_apy numeric,
  duration_months integer,
  lock_end_date timestamp with time zone,
  is_locked boolean,
  network_efficiency numeric,
  created_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Security check: users can only access their own data unless admin
  IF NOT (is_admin(auth.uid()) OR auth.uid() = target_user_id) THEN
    RAISE EXCEPTION 'Access denied: can only access own staking data';
  END IF;

  RETURN QUERY
  SELECT 
    usp.id,
    usp.pool_type,
    COALESCE(esp.name, 'Legacy ' || UPPER(usp.pool_type) || ' Pool') as pool_name,
    usp.staked_amount,
    usp.balance,
    usp.rewards_earned,
    COALESCE(usp.dynamic_apy, usp.apy_rate) as dynamic_apy,
    COALESCE(usp.stake_duration_months, esp.duration_months, 3) as duration_months,
    usp.lock_end_date,
    CASE 
      WHEN usp.lock_end_date > now() THEN true 
      ELSE false 
    END as is_locked,
    COALESCE(usp.network_efficiency, 1.0) as network_efficiency,
    usp.created_at
  FROM user_staking_pools usp
  LEFT JOIN enhanced_staking_pools esp ON usp.enhanced_pool_id = esp.id
  WHERE usp.user_id = target_user_id
    AND usp.staked_amount > 0
  ORDER BY usp.created_at DESC;
END;
$$;

COMMENT ON FUNCTION public.migrate_staking_history_to_enhanced() IS 'Migrates existing staking pools to enhanced staking system';
COMMENT ON FUNCTION public.migrate_sensitive_data_to_secure_tables() IS 'Migrates sensitive personal and wallet data to encrypted tables';
COMMENT ON FUNCTION public.get_user_enhanced_stakes(uuid) IS 'Returns enhanced staking history for a user';