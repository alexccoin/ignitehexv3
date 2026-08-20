-- Fix database function security warnings by setting search_path
ALTER FUNCTION public.update_founder_position() SET search_path = 'public';
ALTER FUNCTION public.calculate_ccos_mint(numeric, text, numeric) SET search_path = 'public';