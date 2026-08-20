-- Create audit log table for private seed str access
CREATE TABLE IF NOT EXISTS public.private_seed_str_access_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id UUID REFERENCES public.private_seed_str_applications(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    action TEXT NOT NULL,
    ip_address INET DEFAULT '0.0.0.0'::inet,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS on access log
ALTER TABLE public.private_seed_str_access_log ENABLE ROW LEVEL SECURITY;

-- Only admins can view access logs
CREATE POLICY "Admins can view private seed str access logs"
ON public.private_seed_str_access_log
FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'seed_str_admin'));

-- Users can insert their own access logs
CREATE POLICY "Users can insert their own access logs"
ON public.private_seed_str_access_log
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);