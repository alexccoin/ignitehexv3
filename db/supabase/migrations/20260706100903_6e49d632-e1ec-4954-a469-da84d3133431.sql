
-- arx_club_members: safe defaults on self-insert
DROP POLICY IF EXISTS "Users can create own arx club membership" ON public.arx_club_members;
CREATE POLICY "Users can create own arx club membership"
ON public.arx_club_members
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND COALESCE(council_member, false) = false
  AND COALESCE(executive_board, false) = false
  AND COALESCE(voting_weight, 1) = 1
  AND COALESCE(kyc_status, 'pending') = 'pending'
  AND (governance_role IS NULL OR governance_role = 'member')
);

-- founder_access: users cannot self-activate
DROP POLICY IF EXISTS "Users can insert their own founder access" ON public.founder_access;
CREATE POLICY "Users can insert their own founder access"
ON public.founder_access
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND COALESCE(is_active, false) = false
);

-- guardian_wallets: force zero balances on self-insert
DROP POLICY IF EXISTS "Users can create their own wallets" ON public.guardian_wallets;
CREATE POLICY "Users can create their own wallets"
ON public.guardian_wallets
FOR INSERT
TO authenticated
WITH CHECK (
  user_id = auth.uid()
  AND COALESCE(balance, 0) = 0
  AND COALESCE(usd_value, 0) = 0
  AND COALESCE(external_balance, 0) = 0
);

-- user_wallets: force zero balances on self-insert
DROP POLICY IF EXISTS "Users can insert their own wallet" ON public.user_wallets;
CREATE POLICY "Users can insert their own wallet"
ON public.user_wallets
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND COALESCE(arss_balance, 0) = 0
  AND COALESCE(total_earned, 0) = 0
  AND COALESCE(total_spent, 0) = 0
);

-- realtime.messages: exact / prefix topic matching, not substring
DROP POLICY IF EXISTS "authenticated_user_scoped_topics" ON realtime.messages;
CREATE POLICY "authenticated_user_scoped_topics"
ON realtime.messages
FOR SELECT
TO authenticated
USING (
  realtime.topic() = (auth.uid())::text
  OR realtime.topic() LIKE ((auth.uid())::text || ':%')
  OR realtime.topic() LIKE ('user:' || (auth.uid())::text)
  OR realtime.topic() LIKE ('user:' || (auth.uid())::text || ':%')
  OR realtime.topic() = 'chat_messages:public'
  OR public.has_role(auth.uid(), 'admin'::app_role)
);
