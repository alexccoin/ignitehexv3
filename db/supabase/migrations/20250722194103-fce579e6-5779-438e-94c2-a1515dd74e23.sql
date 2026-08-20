-- Drop the problematic view and recreate without SECURITY DEFINER
DROP VIEW IF EXISTS founder_position_details;

-- Create a regular view instead
CREATE VIEW founder_position_details AS
SELECT 
  fp.id,
  fp.user_id,
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