-- Fix search path for remaining security definer functions
ALTER FUNCTION public.secure_update_user_profile(jsonb) SET search_path = 'public';
ALTER FUNCTION public.log_security_event(text, text, text, jsonb) SET search_path = 'public';
ALTER FUNCTION public.validate_founder_position_input(jsonb) SET search_path = 'public';