-- Update pending STR voucher package_type labels to reflect $0.005/STR vesting rate
-- This is a DATA update for pending vouchers only (not yet credited)
-- Old labels used $0.00911 rate, new labels use $0.005 rate
-- HISTORY PRESERVED: approved vouchers are NOT changed

UPDATE voucher_redemptions 
SET package_type = 'Foundation ($2500) ≈ 500000.00 STR', updated_at = now()
WHERE status = 'pending' AND lower(token_type) = 'str' 
  AND package_type IN ('Foundation ($2500) ≈ 274423.71 STR', 'Foundation ($2,500) ≈ 274,423.71 STR', 'Foundation ($2,500) ≈ 274,401.67 STR');

UPDATE voucher_redemptions 
SET package_type = 'Pioneer ($5000) ≈ 1000000.00 STR', updated_at = now()
WHERE status = 'pending' AND lower(token_type) = 'str' 
  AND package_type IN ('Pioneer ($5000) ≈ 548847.42 STR', 'Pioneer ($5,000) ≈ 548,847.42 STR', 'Pioneer ($5,000) ≈ 548,803.34 STR');

UPDATE voucher_redemptions 
SET package_type = 'Innovator''s ($10000) ≈ 2000000.00 STR', updated_at = now()
WHERE status = 'pending' AND lower(token_type) = 'str' 
  AND package_type IN ('Innovator''s ($10000) ≈ 1097694.84 STR', 'Innovator''s ($10,000) ≈ 1,097,694.84 STR', 'Innovator''s ($10,000) ≈ 1,097,606.69 STR');

UPDATE voucher_redemptions 
SET package_type = 'Architect''s ($25000) ≈ 5000000.00 STR', updated_at = now()
WHERE status = 'pending' AND lower(token_type) = 'str' 
  AND package_type IN ('Architect''s ($25000) ≈ 2744237.10 STR', 'Architect''s ($25,000) ≈ 2,744,237.10 STR', 'Architect''s ($25,000) ≈ 2,744,016.72 STR');

UPDATE voucher_redemptions 
SET package_type = 'Network Builder''s ($50000) ≈ 10000000.00 STR', updated_at = now()
WHERE status = 'pending' AND lower(token_type) = 'str' 
  AND package_type IN ('Network Builder''s ($50000) ≈ 5488474.20 STR', 'Network Builder''s ($50,000) ≈ 5,488,474.20 STR', 'Network Builder''s ($50,000) ≈ 5,488,033.44 STR');

UPDATE voucher_redemptions 
SET package_type = 'Quantum Core ($100000) ≈ 20000000.00 STR', updated_at = now()
WHERE status = 'pending' AND lower(token_type) = 'str' 
  AND package_type IN ('Quantum Core ($100000) ≈ 10976948.41 STR', 'Quantum Core ($100,000) ≈ 10,976,948.41 STR', 'Quantum Core ($100,000) ≈ 10,976,066.89 STR');