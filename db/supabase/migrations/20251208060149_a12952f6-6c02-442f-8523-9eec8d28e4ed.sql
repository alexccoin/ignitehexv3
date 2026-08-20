-- Fix governance_votes RLS policies - restrict to user's own votes only
-- This is non-destructive: only changes access rules, not data

DROP POLICY IF EXISTS "Public can view votes" ON governance_votes;
DROP POLICY IF EXISTS "Anyone can view votes" ON governance_votes;

-- Create secure user-scoped policy
CREATE POLICY "Users can view their own votes" ON governance_votes
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- Ensure users can still insert their own votes
CREATE POLICY "Users can insert their own votes" ON governance_votes
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);