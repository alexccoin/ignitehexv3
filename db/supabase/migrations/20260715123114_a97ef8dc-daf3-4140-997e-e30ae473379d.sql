-- Restrict safe_purchases INSERT to authenticated users tying rows to their own auth.uid()
DROP POLICY IF EXISTS "Anyone can submit SAFE subscription" ON public.safe_purchases;
CREATE POLICY "Authenticated users submit own SAFE subscription"
ON public.safe_purchases
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- Remove self-insert of arx_club_members; require admin provisioning
DROP POLICY IF EXISTS "Users can create own arx club membership" ON public.arx_club_members;