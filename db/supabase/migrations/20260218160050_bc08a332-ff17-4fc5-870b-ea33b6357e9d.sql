
-- Create missing asset reports table
CREATE TABLE public.missing_asset_reports (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  full_name TEXT,
  email_address TEXT,
  
  -- Asset selections
  starw_nodes_count INTEGER DEFAULT 0,
  supernodes_count INTEGER DEFAULT 0,
  missing_crypto TEXT[] DEFAULT '{}',
  
  -- Comment
  user_comment TEXT,
  
  -- Status management
  status TEXT NOT NULL DEFAULT 'pending', -- pending, approved, declined, suspended
  admin_notes TEXT,
  reviewed_by UUID,
  reviewed_at TIMESTAMP WITH TIME ZONE,
  
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.missing_asset_reports ENABLE ROW LEVEL SECURITY;

-- Users can insert their own reports
CREATE POLICY "Users can create missing asset reports"
ON public.missing_asset_reports
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can view their own reports
CREATE POLICY "Users can view their own reports"
ON public.missing_asset_reports
FOR SELECT
USING (auth.uid() = user_id);

-- Admins can view all reports
CREATE POLICY "Admins can view all missing asset reports"
ON public.missing_asset_reports
FOR SELECT
USING (public.is_admin(auth.uid()));

-- Admins can update reports
CREATE POLICY "Admins can update missing asset reports"
ON public.missing_asset_reports
FOR UPDATE
USING (public.is_admin(auth.uid()));

-- Auto-update timestamp trigger
CREATE TRIGGER update_missing_asset_reports_updated_at
BEFORE UPDATE ON public.missing_asset_reports
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();
