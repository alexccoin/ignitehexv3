-- Create a cache table for staking data
CREATE TABLE IF NOT EXISTS public.staking_data_cache (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cache_key text UNIQUE NOT NULL,
  data jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.staking_data_cache ENABLE ROW LEVEL SECURITY;

-- Admins can read cache
CREATE POLICY "Admins can read staking cache" ON public.staking_data_cache
  FOR SELECT USING (EXISTS (
    SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role = 'admin'
  ));

-- Service role can manage cache
CREATE POLICY "Service role manages cache" ON public.staking_data_cache
  FOR ALL USING (true) WITH CHECK (true);