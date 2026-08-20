-- Create supernodes table
CREATE TABLE IF NOT EXISTS public.supernodes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  node_number INTEGER NOT NULL CHECK (node_number >= 1 AND node_number <= 1000),
  status TEXT NOT NULL DEFAULT 'inactive' CHECK (status IN ('inactive', 'active', 'pending')),
  worker_nodes_count INTEGER NOT NULL DEFAULT 0 CHECK (worker_nodes_count >= 0),
  assigned_by UUID REFERENCES auth.users(id),
  assigned_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id, node_number)
);

-- Enable RLS
ALTER TABLE public.supernodes ENABLE ROW LEVEL SECURITY;

-- Users can view their own supernodes
CREATE POLICY "Users can view their own supernodes"
ON public.supernodes
FOR SELECT
USING (auth.uid() = user_id);

-- Admins can manage all supernodes
CREATE POLICY "Admins can manage all supernodes"
ON public.supernodes
FOR ALL
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- Create indexes
CREATE INDEX idx_supernodes_user_id ON public.supernodes(user_id);
CREATE INDEX idx_supernodes_status ON public.supernodes(status);

-- Trigger to update updated_at
CREATE TRIGGER update_supernodes_updated_at
BEFORE UPDATE ON public.supernodes
FOR EACH ROW
EXECUTE FUNCTION update_personal_nodes_updated_at();