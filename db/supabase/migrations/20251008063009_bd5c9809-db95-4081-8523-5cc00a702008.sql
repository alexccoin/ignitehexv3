-- Create governance_proposals table
CREATE TABLE IF NOT EXISTS public.governance_proposals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  vote_count INTEGER NOT NULL DEFAULT 0,
  support_votes INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  voting_ends_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT (now() + INTERVAL '72 hours')
);

-- Enable RLS
ALTER TABLE public.governance_proposals ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to view all proposals
CREATE POLICY "Anyone can view proposals"
  ON public.governance_proposals
  FOR SELECT
  TO authenticated
  USING (true);

-- Allow authenticated users to create proposals
CREATE POLICY "Users can create proposals"
  ON public.governance_proposals
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Create governance_votes table
CREATE TABLE IF NOT EXISTS public.governance_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  proposal_id UUID NOT NULL REFERENCES public.governance_proposals(id) ON DELETE CASCADE,
  support BOOLEAN NOT NULL,
  voting_power INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id, proposal_id)
);

-- Enable RLS
ALTER TABLE public.governance_votes ENABLE ROW LEVEL SECURITY;

-- Allow users to view all votes
CREATE POLICY "Anyone can view votes"
  ON public.governance_votes
  FOR SELECT
  TO authenticated
  USING (true);

-- Allow users to create their own votes (one per proposal)
CREATE POLICY "Users can vote once per proposal"
  ON public.governance_votes
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Create function to update vote counts
CREATE OR REPLACE FUNCTION public.update_proposal_vote_counts()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger to update vote counts
CREATE TRIGGER update_vote_counts_trigger
  AFTER INSERT ON public.governance_votes
  FOR EACH ROW
  EXECUTE FUNCTION public.update_proposal_vote_counts();

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_proposals_status ON public.governance_proposals(status);
CREATE INDEX IF NOT EXISTS idx_proposals_created_at ON public.governance_proposals(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_votes_proposal_id ON public.governance_votes(proposal_id);
CREATE INDEX IF NOT EXISTS idx_votes_user_id ON public.governance_votes(user_id);