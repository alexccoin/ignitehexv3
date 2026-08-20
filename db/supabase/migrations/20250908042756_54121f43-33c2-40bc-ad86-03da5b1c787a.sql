-- Final security hardening: Fix all remaining functions with mutable search_path
-- This should address all remaining security linter warnings

-- Update all remaining functions that might be missing SET search_path = 'public'
CREATE OR REPLACE FUNCTION public.get_security_metrics(time_period_hours integer DEFAULT 24)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  failed_attempts integer;
  sensitive_data_accesses integer;
  admin_actions integer;
  result jsonb;
BEGIN
  -- Count failed authentication attempts in time period
  SELECT COUNT(*) INTO failed_attempts
  FROM public.auth_attempts
  WHERE success = false
    AND created_at > now() - (time_period_hours || ' hours')::interval;
  
  -- Count sensitive data access events
  SELECT COUNT(*) INTO sensitive_data_accesses
  FROM public.security_audit_log
  WHERE action LIKE 'sensitive_data_%'
    AND created_at > now() - (time_period_hours || ' hours')::interval;
  
  -- Count admin actions
  SELECT COUNT(*) INTO admin_actions
  FROM public.security_audit_log
  WHERE action LIKE 'admin_%'
    AND created_at > now() - (time_period_hours || ' hours')::interval;
  
  result := jsonb_build_object(
    'time_period_hours', time_period_hours,
    'failed_attempts', failed_attempts,
    'sensitive_data_accesses', sensitive_data_accesses,
    'admin_actions', admin_actions,
    'generated_at', now()
  );
  
  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_aggregate_staking_stats()
RETURNS TABLE(total_str_staked numeric, total_str_stakers bigint, total_ccos_staked numeric, total_ccos_stakers bigint, total_domain_staked numeric, total_domain_stakers bigint, total_domains_owned bigint, avg_str_apy numeric, avg_ccos_apy numeric, avg_domain_apy numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    -- STR Pool Stats
    COALESCE(SUM(CASE WHEN pool_type = 'str' THEN staked_amount ELSE 0 END), 0) as total_str_staked,
    COUNT(CASE WHEN pool_type = 'str' AND staked_amount > 0 THEN user_id END) as total_str_stakers,
    
    -- CCOS Pool Stats
    COALESCE(SUM(CASE WHEN pool_type = 'ccos' THEN staked_amount ELSE 0 END), 0) as total_ccos_staked,
    COUNT(CASE WHEN pool_type = 'ccos' AND staked_amount > 0 THEN user_id END) as total_ccos_stakers,
    
    -- Domain Pool Stats
    COALESCE(SUM(CASE WHEN pool_type = 'domain' THEN staked_amount ELSE 0 END), 0) as total_domain_staked,
    COUNT(CASE WHEN pool_type = 'domain' AND staked_amount > 0 THEN user_id END) as total_domain_stakers,
    
    -- Domain Ownership Stats
    (SELECT COUNT(*) FROM user_profiles WHERE str_domain_owned IS NOT NULL AND str_domain_owned != '') as total_domains_owned,
    
    -- Average APY rates
    COALESCE(AVG(CASE WHEN pool_type = 'str' THEN apy_rate END), 0) as avg_str_apy,
    COALESCE(AVG(CASE WHEN pool_type = 'ccos' THEN apy_rate END), 0) as avg_ccos_apy,
    COALESCE(AVG(CASE WHEN pool_type = 'domain' THEN apy_rate END), 0) as avg_domain_apy
    
  FROM user_staking_pools;
END;
$function$;

CREATE OR REPLACE FUNCTION public.log_emergency_security_action(action_user_id uuid, action_type text, action_details jsonb DEFAULT '{}'::jsonb)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  INSERT INTO security_audit_log (
    user_id,
    action,
    resource_type,
    details,
    ip_address
  ) VALUES (
    action_user_id,
    action_type,
    'security_emergency',
    action_details || jsonb_build_object(
      'timestamp', now(),
      'performed_by', auth.uid()
    ),
    get_client_ip()
  );
  
  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.log_critical_security_event(event_type text, details jsonb DEFAULT NULL::jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  INSERT INTO public.security_audit_log (
    user_id,
    action,
    resource_type,
    details,
    ip_address
  ) VALUES (
    auth.uid(),
    'critical_security_' || event_type,
    'security_system',
    COALESCE(details, '{}'),
    get_client_ip()
  );
  
  -- In a production system, you would also send alerts here
  -- For now, we'll just ensure it's logged
END;
$function$;