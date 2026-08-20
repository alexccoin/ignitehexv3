GRANT INSERT ON public.safe_purchases TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.safe_purchases TO authenticated;
GRANT ALL ON public.safe_purchases TO service_role;