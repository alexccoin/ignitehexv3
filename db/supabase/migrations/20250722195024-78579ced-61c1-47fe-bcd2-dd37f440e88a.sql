-- Add position_type field to founder_positions
ALTER TABLE founder_positions ADD COLUMN IF NOT EXISTS position_type text DEFAULT 'standard';

-- Update existing positions to have standard type
UPDATE founder_positions SET position_type = 'standard' WHERE position_type IS NULL;

-- Add constraint for position types
ALTER TABLE founder_positions ADD CONSTRAINT founder_position_type_check 
CHECK (position_type IN ('standard', 'prime'));

-- Update the Prime Founder position to have correct type
UPDATE founder_positions 
SET position_type = 'prime' 
WHERE is_prime = true;