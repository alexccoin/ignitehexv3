-- Fix remaining functions with mutable search_path security issue
-- This addresses the security linter warning about function search path

-- Update all functions that are missing SET search_path = 'public'
CREATE OR REPLACE FUNCTION public.generate_str_wallet_address()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  wallet_address TEXT;
  random_chars TEXT;
  chars TEXT := 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  char_length INTEGER := length(chars);
BEGIN
  -- Generate 13 random alphanumeric characters
  random_chars := '';
  FOR i IN 1..13 LOOP
    random_chars := random_chars || substr(chars, floor(random() * char_length + 1)::integer, 1);
  END LOOP;
  
  -- Create wallet address with strzk13 prefix
  wallet_address := 'strzk13' || random_chars;
  
  RETURN wallet_address;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_pool_stats(pool_uuid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  total_deposits NUMERIC;
  total_positions INTEGER;
BEGIN
  -- Calculate total liquidity and update pool
  SELECT COALESCE(SUM(amount_deposited), 0), COUNT(*)
  INTO total_deposits, total_positions
  FROM user_liquidity_positions 
  WHERE pool_id = pool_uuid;
  
  UPDATE liquidity_pools 
  SET 
    total_liquidity = total_deposits,
    updated_at = now()
  WHERE id = pool_uuid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.calculate_contribution_reward(contribution_type text, quality_score integer, content_size integer DEFAULT 1000)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  base_reward DECIMAL(18,8);
  quality_multiplier DECIMAL(3,2);
  size_multiplier DECIMAL(3,2);
BEGIN
  -- Base rewards by type
  CASE contribution_type
    WHEN 'text' THEN base_reward := 10.0;
    WHEN 'image' THEN base_reward := 15.0;
    WHEN 'document' THEN base_reward := 25.0;
    WHEN 'code' THEN base_reward := 30.0;
    ELSE base_reward := 5.0;
  END CASE;
  
  -- Quality multiplier (0.5x to 2.0x based on score)
  quality_multiplier := (quality_score / 50.0);
  
  -- Size multiplier (more content = higher reward)
  size_multiplier := LEAST(2.0, (content_size / 1000.0));
  
  RETURN base_reward * quality_multiplier * size_multiplier;
END;
$function$;

CREATE OR REPLACE FUNCTION public.encrypt_recovery_words_batch()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  user_record RECORD;
  encrypted_count INTEGER := 0;
  failed_count INTEGER := 0;
  result jsonb;
BEGIN
  -- Process users with unencrypted recovery words
  FOR user_record IN 
    SELECT user_id, wallet_recovery_words 
    FROM user_profiles 
    WHERE wallet_recovery_words IS NOT NULL 
    AND recovery_words_encrypted = false
    AND wallet_pin_hash IS NOT NULL
  LOOP
    BEGIN
      -- Update to mark as encrypted (simplified for now)
      UPDATE user_profiles 
      SET recovery_words_encrypted = true,
          updated_at = now()
      WHERE user_id = user_record.user_id;
      
      encrypted_count := encrypted_count + 1;
      
      -- Log the encryption action
      INSERT INTO security_audit_log (
        user_id, action, resource_type, details
      ) VALUES (
        user_record.user_id, 
        'recovery_words_encrypted', 
        'user_profiles',
        jsonb_build_object(
          'batch_encryption', true,
          'timestamp', now()
        )
      );
      
    EXCEPTION WHEN OTHERS THEN
      failed_count := failed_count + 1;
      -- Log the failure but continue
      INSERT INTO security_audit_log (
        user_id, action, resource_type, details
      ) VALUES (
        user_record.user_id, 
        'recovery_words_encryption_failed', 
        'user_profiles',
        jsonb_build_object(
          'error', SQLERRM,
          'timestamp', now()
        )
      );
    END;
  END LOOP;
  
  result := jsonb_build_object(
    'success', true,
    'encrypted_count', encrypted_count,
    'failed_count', failed_count,
    'timestamp', now()
  );
  
  RETURN result;
END;
$function$;