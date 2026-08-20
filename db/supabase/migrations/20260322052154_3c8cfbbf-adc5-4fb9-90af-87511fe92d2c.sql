
-- 1. Set all STARW nodes to active
UPDATE starw_nodes SET status = 'active', updated_at = now() WHERE status != 'active';

-- 2. Create WSTR rewards table for STARW node holders
CREATE TABLE IF NOT EXISTS public.starw_wstr_rewards (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  starw_node_id UUID NOT NULL REFERENCES starw_nodes(id) ON DELETE CASCADE,
  reward_amount NUMERIC NOT NULL DEFAULT 2.9,
  reward_date DATE NOT NULL DEFAULT CURRENT_DATE,
  status TEXT NOT NULL DEFAULT 'credited',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(starw_node_id, reward_date)
);

-- Enable RLS
ALTER TABLE public.starw_wstr_rewards ENABLE ROW LEVEL SECURITY;

-- Users can view their own rewards
CREATE POLICY "Users can view their own WSTR rewards"
  ON public.starw_wstr_rewards FOR SELECT
  USING (auth.uid() = user_id);

-- Admins can manage all rewards
CREATE POLICY "Admins can manage WSTR rewards"
  ON public.starw_wstr_rewards FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'admin'
    )
  );

-- Index for fast lookups
CREATE INDEX idx_starw_wstr_rewards_user_id ON starw_wstr_rewards(user_id);
CREATE INDEX idx_starw_wstr_rewards_date ON starw_wstr_rewards(reward_date);
CREATE INDEX idx_starw_wstr_rewards_node_date ON starw_wstr_rewards(starw_node_id, reward_date);

-- 3. Create a function to distribute daily WSTR rewards to all active STARW node holders
CREATE OR REPLACE FUNCTION public.distribute_starw_wstr_rewards()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
  v_total_rewards NUMERIC := 0;
  v_reward_per_node NUMERIC := 2.9;
  v_today DATE := CURRENT_DATE;
BEGIN
  -- Insert rewards for all active STARW nodes that haven't been rewarded today
  INSERT INTO starw_wstr_rewards (user_id, starw_node_id, reward_amount, reward_date)
  SELECT 
    sn.user_id,
    sn.id,
    v_reward_per_node,
    v_today
  FROM starw_nodes sn
  WHERE sn.status = 'active'
    AND NOT EXISTS (
      SELECT 1 FROM starw_wstr_rewards r
      WHERE r.starw_node_id = sn.id AND r.reward_date = v_today
    );

  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_total_rewards := v_count * v_reward_per_node;

  RETURN json_build_object(
    'success', true,
    'nodes_rewarded', v_count,
    'total_wstr_distributed', v_total_rewards,
    'reward_date', v_today
  );
END;
$$;
