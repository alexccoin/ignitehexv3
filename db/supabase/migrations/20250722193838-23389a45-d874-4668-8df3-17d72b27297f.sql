-- Create founder position with position 1 specifications
INSERT INTO founder_positions (
  user_id,
  position_number,
  current_usd_value,
  max_usd_limit,
  min_deposit_usd,
  deposit_date,
  withdrawal_available_date,
  expected_btc_return,
  status
) VALUES (
  auth.uid(),
  1,
  350000, -- Assuming ~$70k per BTC for 5 BTC
  1000000,
  10000,
  now(),
  now() + INTERVAL '90 days',
  525000, -- 7.5 BTC expected return in USD
  'active'
);

-- Add additional fields to founder_positions for the specific requirements
ALTER TABLE founder_positions ADD COLUMN IF NOT EXISTS title text DEFAULT 'Founder Position';
ALTER TABLE founder_positions ADD COLUMN IF NOT EXISTS input_btc_amount numeric DEFAULT 0;
ALTER TABLE founder_positions ADD COLUMN IF NOT EXISTS output_btc_amount numeric DEFAULT 0;
ALTER TABLE founder_positions ADD COLUMN IF NOT EXISTS ccos_mint_percentage numeric DEFAULT 0;
ALTER TABLE founder_positions ADD COLUMN IF NOT EXISTS withdrawal_address text;
ALTER TABLE founder_positions ADD COLUMN IF NOT EXISTS access_password text;
ALTER TABLE founder_positions ADD COLUMN IF NOT EXISTS is_prime boolean DEFAULT false;

-- Update position 1 with specific details
UPDATE founder_positions 
SET 
  title = 'Prime Founder',
  input_btc_amount = 5.0,
  output_btc_amount = 7.5,
  ccos_mint_percentage = 50.0,
  withdrawal_address = 'bc1q9u3hth4x4hl6y8hmcmvm5pc7yvtrduc92rfhxh',
  access_password = 'Joerg1234@',
  is_prime = true
WHERE position_number = 1;

-- Create a view for private link access
CREATE OR REPLACE VIEW founder_position_details AS
SELECT 
  fp.id,
  fp.unique_link_id,
  fp.position_number,
  fp.title,
  fp.input_btc_amount,
  fp.output_btc_amount,
  fp.current_usd_value,
  fp.expected_btc_return,
  fp.ccos_mint_percentage,
  fp.withdrawal_address,
  fp.deposit_date,
  fp.withdrawal_available_date,
  fp.status,
  fp.is_prime,
  CASE 
    WHEN fp.withdrawal_available_date <= now() THEN true
    ELSE false
  END as is_withdrawal_ready
FROM founder_positions fp;

-- Enable RLS on the view
ALTER VIEW founder_position_details SET (security_invoker = true);