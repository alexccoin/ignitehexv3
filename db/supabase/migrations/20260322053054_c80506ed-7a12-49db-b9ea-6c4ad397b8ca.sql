
-- Credit locked $50K $STR per supernode to new holders
-- Johannes Bertele: 2 supernodes = $100,000 (locked)
-- Rene Suess: 1 supernode = $50,000 (locked)
-- Christine Zeitler: 1 supernode = $50,000 (locked)
INSERT INTO fiat_wallets (user_id, currency, balance, available_balance, held_balance)
VALUES 
  ('5c1015a6-d3c9-4576-b10a-76d10af72952', 'USD', 100000, 0, 100000),
  ('106d16d1-d0ae-4df4-ad66-93100498e5ee', 'USD', 50000, 0, 50000),
  ('70c48bc3-6de2-4348-aeee-85ad6c5636e2', 'USD', 50000, 0, 50000)
ON CONFLICT (user_id, currency) DO UPDATE SET 
  balance = fiat_wallets.balance + EXCLUDED.balance,
  held_balance = fiat_wallets.held_balance + EXCLUDED.held_balance,
  updated_at = now();

-- Create supernode wSTR rewards table
CREATE TABLE IF NOT EXISTS public.supernode_wstr_rewards (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  supernode_id UUID NOT NULL REFERENCES supernodes(id) ON DELETE CASCADE,
  reward_amount NUMERIC NOT NULL DEFAULT 27.7,
  reward_date DATE NOT NULL DEFAULT CURRENT_DATE,
  status TEXT NOT NULL DEFAULT 'credited',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(supernode_id, reward_date)
);

ALTER TABLE public.supernode_wstr_rewards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own supernode WSTR rewards"
  ON public.supernode_wstr_rewards FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Admins can manage supernode WSTR rewards"
  ON public.supernode_wstr_rewards FOR ALL
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

CREATE INDEX idx_supernode_wstr_rewards_user_id ON supernode_wstr_rewards(user_id);
CREATE INDEX idx_supernode_wstr_rewards_date ON supernode_wstr_rewards(reward_date);
CREATE INDEX idx_supernode_wstr_rewards_node_date ON supernode_wstr_rewards(supernode_id, reward_date);

-- Create distribution function for supernode wSTR rewards (27.7 per supernode per day)
CREATE OR REPLACE FUNCTION public.distribute_supernode_wstr_rewards()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
  v_total_rewards NUMERIC := 0;
  v_reward_per_node NUMERIC := 27.7;
  v_today DATE := CURRENT_DATE;
BEGIN
  INSERT INTO supernode_wstr_rewards (user_id, supernode_id, reward_amount, reward_date)
  SELECT 
    sn.user_id,
    sn.id,
    v_reward_per_node,
    v_today
  FROM supernodes sn
  WHERE sn.status = 'active'
    AND NOT EXISTS (
      SELECT 1 FROM supernode_wstr_rewards r
      WHERE r.supernode_id = sn.id AND r.reward_date = v_today
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
