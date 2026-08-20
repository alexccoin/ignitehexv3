-- Fix 1: Remove user_id IS NULL exposure from ccos_purchases
DROP POLICY IF EXISTS "Users can view own CCOS purchases" ON public.ccos_purchases;
CREATE POLICY "Users can view own CCOS purchases"
ON public.ccos_purchases FOR SELECT TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own CCOS purchases" ON public.ccos_purchases;
CREATE POLICY "Users can insert own CCOS purchases"
ON public.ccos_purchases FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Fix 2: Restrict token_marketplace_listings to authenticated users only
DROP POLICY IF EXISTS "Anyone can view active token listings" ON public.token_marketplace_listings;
CREATE POLICY "Authenticated users can view active token listings"
ON public.token_marketplace_listings FOR SELECT TO authenticated
USING ((status = 'active') OR (seller_id = auth.uid()));

DROP POLICY IF EXISTS "Users can create own token listings" ON public.token_marketplace_listings;
CREATE POLICY "Users can create own token listings"
ON public.token_marketplace_listings FOR INSERT TO authenticated
WITH CHECK (auth.uid() = seller_id);

DROP POLICY IF EXISTS "Users can update own token listings" ON public.token_marketplace_listings;
CREATE POLICY "Users can update own token listings"
ON public.token_marketplace_listings FOR UPDATE TO authenticated
USING (auth.uid() = seller_id);