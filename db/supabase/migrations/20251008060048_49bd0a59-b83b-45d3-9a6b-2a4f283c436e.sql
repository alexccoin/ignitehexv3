-- Create personal_nodes table for users with STR domains
CREATE TABLE IF NOT EXISTS public.personal_nodes (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  node_number INTEGER NOT NULL,
  node_name TEXT NOT NULL DEFAULT 'Personal Node',
  str_domain TEXT NOT NULL,
  wallet_address TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id),
  UNIQUE(node_number)
);

-- Create index for faster lookups
CREATE INDEX idx_personal_nodes_user_id ON public.personal_nodes(user_id);
CREATE INDEX idx_personal_nodes_str_domain ON public.personal_nodes(str_domain);

-- Enable RLS
ALTER TABLE public.personal_nodes ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own personal node"
  ON public.personal_nodes
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own personal node"
  ON public.personal_nodes
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own personal node"
  ON public.personal_nodes
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can manage all personal nodes"
  ON public.personal_nodes
  FOR ALL
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- Function to get next available node number starting from 1313
CREATE OR REPLACE FUNCTION get_next_node_number()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  next_number INTEGER;
BEGIN
  SELECT COALESCE(MAX(node_number), 1312) + 1
  INTO next_number
  FROM personal_nodes;
  
  -- Ensure it starts from at least 1313
  IF next_number < 1313 THEN
    next_number := 1313;
  END IF;
  
  RETURN next_number;
END;
$$;

-- Function to automatically create personal node when user has STR domain
CREATE OR REPLACE FUNCTION create_personal_node_for_user(
  p_user_id UUID,
  p_str_domain TEXT,
  p_wallet_address TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_node_id UUID;
  v_node_number INTEGER;
BEGIN
  -- Check if node already exists for this user
  SELECT id INTO v_node_id
  FROM personal_nodes
  WHERE user_id = p_user_id;
  
  IF v_node_id IS NOT NULL THEN
    -- Update existing node
    UPDATE personal_nodes
    SET 
      str_domain = p_str_domain,
      wallet_address = p_wallet_address,
      updated_at = now()
    WHERE id = v_node_id;
    
    RETURN v_node_id;
  END IF;
  
  -- Get next node number
  v_node_number := get_next_node_number();
  
  -- Create new personal node
  INSERT INTO personal_nodes (
    user_id,
    node_number,
    node_name,
    str_domain,
    wallet_address
  ) VALUES (
    p_user_id,
    v_node_number,
    'Personal Node',
    p_str_domain,
    p_wallet_address
  )
  RETURNING id INTO v_node_id;
  
  RETURN v_node_id;
END;
$$;

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_personal_nodes_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER personal_nodes_updated_at
  BEFORE UPDATE ON personal_nodes
  FOR EACH ROW
  EXECUTE FUNCTION update_personal_nodes_updated_at();