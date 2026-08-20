-- Fix the search path warning by updating the new functions
ALTER FUNCTION public.validate_sensitive_operation(uuid, text, inet) SET search_path = 'public';
ALTER FUNCTION public.log_sensitive_access() SET search_path = 'public';
ALTER FUNCTION public.validate_wallet_pin_secure_fixed(uuid, text, inet) SET search_path = 'public';
ALTER FUNCTION public.run_critical_security_fixes() SET search_path = 'public';
ALTER FUNCTION public.sanitize_user_input(text, integer, boolean) SET search_path = 'public';