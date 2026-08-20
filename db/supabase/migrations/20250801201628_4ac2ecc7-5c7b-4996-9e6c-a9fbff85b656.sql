-- Fix search path for security
ALTER FUNCTION public.get_aggregate_staking_stats() SET search_path = 'public';
ALTER FUNCTION public.get_total_ecosystem_value() SET search_path = 'public';