-- ARX CLUB GOVERNANCE PORTAL DATABASE SCHEMA

-- Extend arx_club_members with governance roles
ALTER TABLE public.arx_club_members 
ADD COLUMN IF NOT EXISTS governance_role TEXT DEFAULT 'member',
ADD COLUMN IF NOT EXISTS council_member BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS executive_board BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS voting_weight INTEGER DEFAULT 1,
ADD COLUMN IF NOT EXISTS node_operator BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS kyc_status TEXT DEFAULT 'pending',
ADD COLUMN IF NOT EXISTS kyc_verified_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS wNFT_credential TEXT,
ADD COLUMN IF NOT EXISTS activation_hash TEXT;

-- Member registry and KYC
CREATE TABLE IF NOT EXISTS public.arx_member_registry (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id UUID NOT NULL REFERENCES public.arx_club_members(id) ON DELETE CASCADE,
  legal_name TEXT NOT NULL,
  entity_type TEXT NOT NULL DEFAULT 'individual',
  jurisdiction TEXT,
  kyc_documents JSONB DEFAULT '[]',
  verification_status TEXT NOT NULL DEFAULT 'pending',
  verified_by UUID,
  verified_at TIMESTAMP WITH TIME ZONE,
  node_id TEXT,
  node_status TEXT DEFAULT 'inactive',
  signing_key_hash TEXT,
  domain_verified BOOLEAN DEFAULT false,
  domain_records JSONB DEFAULT '[]',
  asset_verification JSONB DEFAULT '{}',
  activation_snapshot_hash TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Invitations
CREATE TABLE IF NOT EXISTS public.arx_invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invited_by UUID NOT NULL,
  email TEXT NOT NULL,
  invitation_code TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  accepted_at TIMESTAMP WITH TIME ZONE,
  accepted_by UUID,
  status TEXT NOT NULL DEFAULT 'pending',
  role_preset TEXT DEFAULT 'member',
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Treasury Pools
CREATE TABLE IF NOT EXISTS public.arx_treasury_pools (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pool_name TEXT NOT NULL UNIQUE,
  pool_type TEXT NOT NULL,
  balance_arx NUMERIC DEFAULT 0,
  balance_ars NUMERIC DEFAULT 0,
  balance_usd NUMERIC DEFAULT 0,
  locked_amount NUMERIC DEFAULT 0,
  lock_schedule JSONB DEFAULT '[]',
  release_calendar JSONB DEFAULT '[]',
  multisig_threshold INTEGER NOT NULL DEFAULT 3,
  multisig_signers JSONB DEFAULT '[]',
  oracle_price_feed TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Treasury Transactions
CREATE TABLE IF NOT EXISTS public.arx_treasury_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pool_id UUID NOT NULL REFERENCES public.arx_treasury_pools(id),
  transaction_type TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  currency TEXT NOT NULL,
  usd_equivalent NUMERIC,
  oracle_rate NUMERIC,
  initiated_by UUID NOT NULL,
  multisig_approval_hash TEXT,
  required_signatures INTEGER NOT NULL,
  collected_signatures JSONB DEFAULT '[]',
  status TEXT NOT NULL DEFAULT 'pending',
  executed_at TIMESTAMP WITH TIME ZONE,
  attestation_hash TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- wNFT Management
CREATE TABLE IF NOT EXISTS public.arx_wnft_registry (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id UUID NOT NULL REFERENCES public.arx_club_members(id),
  credential_code TEXT NOT NULL UNIQUE,
  token_id TEXT,
  minted_at TIMESTAMP WITH TIME ZONE,
  transfer_restricted BOOLEAN DEFAULT true,
  metadata JSONB DEFAULT '{}',
  attestation_hash TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Voting Ballots
CREATE TABLE IF NOT EXISTS public.arx_voting_ballots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT,
  ballot_type TEXT NOT NULL DEFAULT 'on-chain',
  created_by UUID NOT NULL,
  voting_start TIMESTAMP WITH TIME ZONE NOT NULL,
  voting_end TIMESTAMP WITH TIME ZONE NOT NULL,
  quorum_required INTEGER DEFAULT 51,
  snapshot_block TEXT,
  snapshot_hash TEXT,
  oracle_data JSONB DEFAULT '{}',
  worker_node_signatures JSONB DEFAULT '[]',
  results JSONB DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'draft',
  published_at TIMESTAMP WITH TIME ZONE,
  attestation_hash TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Voting Records
CREATE TABLE IF NOT EXISTS public.arx_voting_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ballot_id UUID NOT NULL REFERENCES public.arx_voting_ballots(id),
  voter_id UUID NOT NULL,
  vote_choice TEXT NOT NULL,
  voting_weight INTEGER NOT NULL DEFAULT 1,
  signature_hash TEXT,
  voted_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(ballot_id, voter_id)
);

-- Documentation Vault
CREATE TABLE IF NOT EXISTS public.arx_documentation_vault (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_title TEXT NOT NULL,
  document_type TEXT NOT NULL,
  file_path TEXT,
  encrypted BOOLEAN DEFAULT true,
  encryption_key_id TEXT,
  access_level TEXT NOT NULL DEFAULT 'executive',
  allowed_roles JSONB DEFAULT '["executive_board"]',
  redacted_sections JSONB DEFAULT '[]',
  zk_proof_available BOOLEAN DEFAULT false,
  uploaded_by UUID NOT NULL,
  attestation_hash TEXT,
  access_log JSONB DEFAULT '[]',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Events and Meetings
CREATE TABLE IF NOT EXISTS public.arx_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_title TEXT NOT NULL,
  event_type TEXT NOT NULL,
  description TEXT,
  scheduled_at TIMESTAMP WITH TIME ZONE NOT NULL,
  duration_minutes INTEGER DEFAULT 60,
  location TEXT,
  virtual_meeting_link TEXT,
  access_level TEXT NOT NULL DEFAULT 'members',
  allowed_roles JSONB DEFAULT '["member"]',
  agenda JSONB DEFAULT '[]',
  minutes_document_id UUID,
  attestation_hash TEXT,
  status TEXT NOT NULL DEFAULT 'scheduled',
  created_by UUID NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Meeting Attendees
CREATE TABLE IF NOT EXISTS public.arx_event_attendees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES public.arx_events(id) ON DELETE CASCADE,
  member_id UUID NOT NULL,
  rsvp_status TEXT DEFAULT 'pending',
  attended BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(event_id, member_id)
);

-- Support Tickets
CREATE TABLE IF NOT EXISTS public.arx_support_tickets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_number TEXT NOT NULL UNIQUE,
  submitted_by UUID NOT NULL,
  priority TEXT NOT NULL DEFAULT 'normal',
  category TEXT NOT NULL,
  subject TEXT NOT NULL,
  description TEXT,
  status TEXT NOT NULL DEFAULT 'open',
  assigned_to UUID,
  escalation_level INTEGER DEFAULT 0,
  sla_deadline TIMESTAMP WITH TIME ZONE,
  resolved_at TIMESTAMP WITH TIME ZONE,
  attestation_hash TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Legal and Audit Reports
CREATE TABLE IF NOT EXISTS public.arx_legal_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_type TEXT NOT NULL,
  report_title TEXT NOT NULL,
  fiscal_period TEXT,
  document_id UUID REFERENCES public.arx_documentation_vault(id),
  published_by UUID NOT NULL,
  published_at TIMESTAMP WITH TIME ZONE,
  attestation_hash TEXT NOT NULL,
  verifier_metadata JSONB DEFAULT '{}',
  signatures JSONB DEFAULT '[]',
  status TEXT NOT NULL DEFAULT 'draft',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Audit Trail
CREATE TABLE IF NOT EXISTS public.arx_audit_trail (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  action_type TEXT NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id TEXT NOT NULL,
  performed_by UUID NOT NULL,
  ip_address INET,
  user_agent TEXT,
  changes JSONB DEFAULT '{}',
  attestation_hash TEXT,
  timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS on all tables
ALTER TABLE public.arx_member_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arx_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arx_treasury_pools ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arx_treasury_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arx_wnft_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arx_voting_ballots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arx_voting_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arx_documentation_vault ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arx_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arx_event_attendees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arx_support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arx_legal_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arx_audit_trail ENABLE ROW LEVEL SECURITY;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_arx_registry_member ON public.arx_member_registry(member_id);
CREATE INDEX IF NOT EXISTS idx_arx_treasury_tx_pool ON public.arx_treasury_transactions(pool_id);
CREATE INDEX IF NOT EXISTS idx_arx_voting_ballot ON public.arx_voting_records(ballot_id);
CREATE INDEX IF NOT EXISTS idx_arx_events_date ON public.arx_events(scheduled_at);
CREATE INDEX IF NOT EXISTS idx_arx_support_status ON public.arx_support_tickets(status);

-- RLS Policies for members
CREATE POLICY "Members view own registry" ON public.arx_member_registry
  FOR SELECT USING (
    member_id IN (
      SELECT id FROM public.arx_club_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Executive board view all registry" ON public.arx_member_registry
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.arx_club_members
      WHERE user_id = auth.uid() AND executive_board = true
    )
  );

-- Treasury access
CREATE POLICY "Council view treasury" ON public.arx_treasury_pools
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.arx_club_members
      WHERE user_id = auth.uid() AND (council_member = true OR executive_board = true)
    )
  );

-- Voting access
CREATE POLICY "Members view active ballots" ON public.arx_voting_ballots
  FOR SELECT USING (
    status = 'active' AND EXISTS (
      SELECT 1 FROM public.arx_club_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Members can vote" ON public.arx_voting_records
  FOR INSERT WITH CHECK (
    voter_id IN (SELECT id FROM public.arx_club_members WHERE user_id = auth.uid())
  );

-- Documentation access based on roles
CREATE POLICY "Documentation role-based access" ON public.arx_documentation_vault
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.arx_club_members
      WHERE user_id = auth.uid()
      AND (
        (executive_board = true) OR
        (governance_role = ANY(SELECT jsonb_array_elements_text(allowed_roles)))
      )
    )
  );

-- Support tickets
CREATE POLICY "Members manage own tickets" ON public.arx_support_tickets
  FOR ALL USING (
    submitted_by = (SELECT id FROM public.arx_club_members WHERE user_id = auth.uid())
  );

-- Admin full access
CREATE POLICY "Admins manage all arx governance" ON public.arx_member_registry
  FOR ALL USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins manage invitations" ON public.arx_invitations
  FOR ALL USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins manage treasury" ON public.arx_treasury_pools
  FOR ALL USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins manage voting" ON public.arx_voting_ballots
  FOR ALL USING (public.has_role(auth.uid(), 'admin'));

-- Audit log
CREATE POLICY "Audit log insert" ON public.arx_audit_trail
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Executive view audit" ON public.arx_audit_trail
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.arx_club_members
      WHERE user_id = auth.uid() AND executive_board = true
    )
  );