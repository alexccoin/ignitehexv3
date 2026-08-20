-- Create domains table for STR.DOMAINS minting system
CREATE TABLE IF NOT EXISTS public.str_domains (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  domain_name TEXT NOT NULL,
  domain_type TEXT NOT NULL CHECK (domain_type IN ('personal', 'business', 'premium', 'brand')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'minted', 'rejected')),
  minted_at TIMESTAMP WITH TIME ZONE,
  approved_by UUID REFERENCES auth.users(id),
  approved_at TIMESTAMP WITH TIME ZONE,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT unique_domain_name UNIQUE (domain_name)
);

-- Enable RLS
ALTER TABLE public.str_domains ENABLE ROW LEVEL SECURITY;

-- Users can view their own domains
CREATE POLICY "Users can view own domains"
  ON public.str_domains
  FOR SELECT
  USING (auth.uid() = user_id);

-- Users can insert their own domain requests
CREATE POLICY "Users can request domains"
  ON public.str_domains
  FOR INSERT
  WITH CHECK (auth.uid() = user_id AND status = 'pending');

-- Users can update their own pending domains
CREATE POLICY "Users can update own pending domains"
  ON public.str_domains
  FOR UPDATE
  USING (auth.uid() = user_id AND status = 'pending')
  WITH CHECK (auth.uid() = user_id);

-- Admins can view all domains
CREATE POLICY "Admins view all domains"
  ON public.str_domains
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM user_roles 
      WHERE user_id = auth.uid() AND role = 'admin'
    )
  );

-- Admins can approve/mint domains
CREATE POLICY "Admins manage all domains"
  ON public.str_domains
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM user_roles 
      WHERE user_id = auth.uid() AND role = 'admin'
    )
  );

-- Create index for domain name lookups
CREATE INDEX idx_str_domains_name ON public.str_domains(domain_name);
CREATE INDEX idx_str_domains_user ON public.str_domains(user_id);
CREATE INDEX idx_str_domains_status ON public.str_domains(status);

-- Create trigger for updated_at
CREATE OR REPLACE FUNCTION update_str_domains_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_str_domains_updated_at
  BEFORE UPDATE ON public.str_domains
  FOR EACH ROW
  EXECUTE FUNCTION update_str_domains_updated_at();

-- Log domain minting events
CREATE OR REPLACE FUNCTION log_domain_mint()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'minted' AND OLD.status != 'minted' THEN
    INSERT INTO security_audit_log (
      user_id, action, resource_type, resource_id, details
    ) VALUES (
      NEW.user_id,
      'domain_minted',
      'str_domains',
      NEW.id::text,
      jsonb_build_object(
        'domain_name', NEW.domain_name,
        'domain_type', NEW.domain_type,
        'approved_by', NEW.approved_by,
        'minted_at', NEW.minted_at
      )
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE TRIGGER trigger_log_domain_mint
  AFTER UPDATE ON public.str_domains
  FOR EACH ROW
  EXECUTE FUNCTION log_domain_mint();