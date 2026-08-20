-- Fix linter: set search_path on function and add public read policies
DROP FUNCTION IF EXISTS public.update_proposal_vote_counts() CASCADE;

CREATE OR REPLACE FUNCTION public.update_proposal_vote_counts()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.governance_proposals
  SET 
    vote_count = (
      SELECT COUNT(*) 
      FROM public.governance_votes 
      WHERE proposal_id = NEW.proposal_id
    ),
    support_votes = (
      SELECT COUNT(*) 
      FROM public.governance_votes 
      WHERE proposal_id = NEW.proposal_id AND support = true
    ),
    updated_at = now()
  WHERE id = NEW.proposal_id;
  
  RETURN NEW;
END;
$$;

-- Recreate trigger
DROP TRIGGER IF EXISTS update_vote_counts_trigger ON public.governance_votes;
CREATE TRIGGER update_vote_counts_trigger
  AFTER INSERT ON public.governance_votes
  FOR EACH ROW
  EXECUTE FUNCTION public.update_proposal_vote_counts();

-- Allow unauthenticated (public) to view proposals and votes
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'governance_proposals' AND policyname = 'Public can view proposals'
  ) THEN
    CREATE POLICY "Public can view proposals"
      ON public.governance_proposals
      FOR SELECT
      TO public
      USING (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'governance_votes' AND policyname = 'Public can view votes'
  ) THEN
    CREATE POLICY "Public can view votes"
      ON public.governance_votes
      FOR SELECT
      TO public
      USING (true);
  END IF;
END $$;