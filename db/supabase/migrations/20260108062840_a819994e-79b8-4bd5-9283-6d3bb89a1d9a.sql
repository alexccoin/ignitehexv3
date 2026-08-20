-- Table to track CCoin Bank cancellation requests
CREATE TABLE public.ccoin_bank_cancellations (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_email TEXT,
  user_full_name TEXT,
  str_domain TEXT,
  
  -- Request details
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'held', 'rejected')),
  
  -- Admin processing
  processed_by UUID REFERENCES auth.users(id),
  processed_at TIMESTAMPTZ,
  admin_notes TEXT,
  
  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.ccoin_bank_cancellations ENABLE ROW LEVEL SECURITY;

-- Users can view their own cancellation requests
CREATE POLICY "Users can view own cancellations"
ON public.ccoin_bank_cancellations
FOR SELECT
USING (auth.uid() = user_id);

-- Users can create their own cancellation request
CREATE POLICY "Users can create own cancellation request"
ON public.ccoin_bank_cancellations
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Admins can view all cancellations
CREATE POLICY "Admins can view all cancellations"
ON public.ccoin_bank_cancellations
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- Admins can update cancellations
CREATE POLICY "Admins can update cancellations"
ON public.ccoin_bank_cancellations
FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- Admins can delete cancellations
CREATE POLICY "Admins can delete cancellations"
ON public.ccoin_bank_cancellations
FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- History table for audit trail
CREATE TABLE public.ccoin_bank_cancellation_history (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  cancellation_id UUID NOT NULL REFERENCES public.ccoin_bank_cancellations(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  old_status TEXT,
  new_status TEXT,
  performed_by UUID REFERENCES auth.users(id),
  notes TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS for history
ALTER TABLE public.ccoin_bank_cancellation_history ENABLE ROW LEVEL SECURITY;

-- Admins can view all history
CREATE POLICY "Admins can view cancellation history"
ON public.ccoin_bank_cancellation_history
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- Admins can insert history
CREATE POLICY "Admins can insert cancellation history"
ON public.ccoin_bank_cancellation_history
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- Trigger to update updated_at
CREATE TRIGGER update_ccoin_bank_cancellations_updated_at
BEFORE UPDATE ON public.ccoin_bank_cancellations
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- Indexes for performance
CREATE INDEX idx_ccoin_bank_cancellations_user_id ON public.ccoin_bank_cancellations(user_id);
CREATE INDEX idx_ccoin_bank_cancellations_status ON public.ccoin_bank_cancellations(status);
CREATE INDEX idx_ccoin_bank_cancellation_history_cancellation_id ON public.ccoin_bank_cancellation_history(cancellation_id);