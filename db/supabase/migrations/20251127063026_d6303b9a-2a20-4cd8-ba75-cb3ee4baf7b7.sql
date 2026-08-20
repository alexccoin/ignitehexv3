-- Fix CCOS vouchers that have incorrect STR package names
-- CCOS should show ~555.56 tokens for $5000, not 548,803.34 STR

-- Update Pioneer ($5000) CCOS vouchers
UPDATE voucher_redemptions
SET package_type = 'Pioneer ($5,000) ≈ 555.56 CCOS'
WHERE token_type = 'ccos' 
AND package_type LIKE '%Pioneer%$5,000%STR%';

-- Update Foundation ($2500) CCOS vouchers
UPDATE voucher_redemptions
SET package_type = 'Foundation ($2,500) ≈ 277.78 CCOS'
WHERE token_type = 'ccos' 
AND package_type LIKE '%Foundation%$2,500%STR%';

-- Update Innovator's ($10000) CCOS vouchers
UPDATE voucher_redemptions
SET package_type = 'Innovator''s ($10,000) ≈ 1,111.11 CCOS'
WHERE token_type = 'ccos' 
AND package_type LIKE '%Innovator%$10,000%STR%';

-- Update Architect's ($25000) CCOS vouchers
UPDATE voucher_redemptions
SET package_type = 'Architect''s ($25,000) ≈ 2,777.78 CCOS'
WHERE token_type = 'ccos' 
AND package_type LIKE '%Architect%$25,000%STR%';

-- Update Network Builder's ($50000) CCOS vouchers
UPDATE voucher_redemptions
SET package_type = 'Network Builder''s ($50,000) ≈ 5,555.56 CCOS'
WHERE token_type = 'ccos' 
AND package_type LIKE '%Network Builder%$50,000%STR%';

-- Update Quantum Core ($100000) CCOS vouchers
UPDATE voucher_redemptions
SET package_type = 'Quantum Core ($100,000) ≈ 11,111.11 CCOS'
WHERE token_type = 'ccos' 
AND package_type LIKE '%Quantum Core%$100,000%STR%';

-- Add comment to document this fix
COMMENT ON TABLE voucher_redemptions IS 'Voucher redemptions table. CRITICAL: package_type must match token_type - CCOS vouchers must show CCOS token amounts (~555 for $5k), not STR amounts (~548k for $5k).';