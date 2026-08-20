
-- 1. Grants (table had no grants -> nothing was readable via Data API)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.safe_purchases TO authenticated;
GRANT INSERT ON public.safe_purchases TO anon;
GRANT ALL ON public.safe_purchases TO service_role;

-- 2. Backfill user_id on credited rows by matching email -> user_profiles
UPDATE public.safe_purchases sp
SET user_id = up.user_id
FROM public.user_profiles up
WHERE sp.user_id IS NULL
  AND sp.email IS NOT NULL
  AND LOWER(up.email_address) = LOWER(sp.email);
