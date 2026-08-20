-- Insert default enhanced pools for all token types
INSERT INTO enhanced_staking_pools (name, token_type, duration_months, apr_min, apr_max, theme, description, icon, min_stake_amount, max_stake_amount) VALUES
-- STR Pools
('STR Spark Pool', 'str', 3, 11, 13, 'Quick ignition for STR tokens', 'Fast-track your STR rewards with our 3-month commitment pool', 'zap', 1000, 10000000),
('STR Pulse Vault', 'str', 6, 13.5, 16, 'Steady rhythm for STR growth', 'Medium-term STR staking with balanced risk and reward', 'activity', 1000, 10000000),
('STR Momentum Lock', 'str', 12, 18, 22, 'Annual STR commitment', 'One-year STR staking for serious long-term holders', 'trending-up', 1000, 10000000),
('STR Gravity Stake', 'str', 24, 28, 35, 'Long-term STR stability', 'Two-year commitment for maximum STR yield potential', 'anchor', 1000, 10000000),
('STR Eclipse Reserve', 'str', 48, 65, 75, 'Full-cycle STR staking', 'Four-year ultra-premium STR staking experience', 'sun', 1000, 10000000),

-- CCOS Pools  
('CCOS Spark Pool', 'ccos', 3, 12.5, 14.5, 'Quick ignition for CCOS tokens', 'Fast-track your CCOS rewards with our 3-month commitment pool', 'zap', 1000, 10000000),
('CCOS Pulse Vault', 'ccos', 6, 15, 17.5, 'Steady rhythm for CCOS growth', 'Medium-term CCOS staking with balanced risk and reward', 'activity', 1000, 10000000),
('CCOS Momentum Lock', 'ccos', 12, 20, 24, 'Annual CCOS commitment', 'One-year CCOS staking for serious long-term holders', 'trending-up', 1000, 10000000),
('CCOS Gravity Stake', 'ccos', 24, 30, 37, 'Long-term CCOS stability', 'Two-year commitment for maximum CCOS yield potential', 'anchor', 1000, 10000000),
('CCOS Eclipse Reserve', 'ccos', 48, 67, 77, 'Full-cycle CCOS staking', 'Four-year ultra-premium CCOS staking experience', 'sun', 1000, 10000000),

-- Domain Pools
('Domain Spark Pool', 'domain', 3, 13, 15, 'Quick ignition for Domain tokens', 'Fast-track your Domain rewards with our 3-month commitment pool', 'zap', 100, 1000000),
('Domain Pulse Vault', 'domain', 6, 16, 18.5, 'Steady rhythm for Domain growth', 'Medium-term Domain staking with balanced risk and reward', 'activity', 100, 1000000),
('Domain Momentum Lock', 'domain', 12, 21, 25, 'Annual Domain commitment', 'One-year Domain staking for serious long-term holders', 'trending-up', 100, 1000000),
('Domain Gravity Stake', 'domain', 24, 32, 39, 'Long-term Domain stability', 'Two-year commitment for maximum Domain yield potential', 'anchor', 100, 1000000),
('Domain Eclipse Reserve', 'domain', 48, 70, 80, 'Full-cycle Domain staking', 'Four-year ultra-premium Domain staking experience', 'sun', 100, 1000000)

ON CONFLICT (name, token_type, duration_months) DO UPDATE SET
  apr_min = EXCLUDED.apr_min,
  apr_max = EXCLUDED.apr_max,
  theme = EXCLUDED.theme,
  description = EXCLUDED.description,
  icon = EXCLUDED.icon,
  min_stake_amount = EXCLUDED.min_stake_amount,
  max_stake_amount = EXCLUDED.max_stake_amount,
  updated_at = now();