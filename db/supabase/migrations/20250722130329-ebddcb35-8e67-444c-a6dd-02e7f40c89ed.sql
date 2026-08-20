-- Add withdrawal tracking to founder positions
ALTER TABLE founder_positions ADD COLUMN IF NOT EXISTS deposit_date timestamp with time zone;
ALTER TABLE founder_positions ADD COLUMN IF NOT EXISTS withdrawal_available_date timestamp with time zone;
ALTER TABLE founder_positions ADD COLUMN IF NOT EXISTS unique_link_id uuid DEFAULT gen_random_uuid();
ALTER TABLE founder_positions ADD COLUMN IF NOT EXISTS expected_btc_return numeric DEFAULT 0;

-- Create unique index on link_id
CREATE UNIQUE INDEX IF NOT EXISTS idx_founder_positions_unique_link_id ON founder_positions(unique_link_id);

-- Update existing positions to set dates and return calculations
UPDATE founder_positions 
SET 
  deposit_date = created_at,
  withdrawal_available_date = created_at + INTERVAL '90 days',
  expected_btc_return = current_usd_value * 1.5 -- 50% return
WHERE deposit_date IS NULL;