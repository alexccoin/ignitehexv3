-- Safe PIN System Reset Migration v2
-- This migration clears all PIN data to force fresh PIN setup for all users
-- NO user accounts or other data will be affected

-- Step 1: Clear all PIN hashes from user profiles (safe - only affects PIN field)
UPDATE user_profiles 
SET wallet_pin_hash = NULL,
    updated_at = now()
WHERE wallet_pin_hash IS NOT NULL;

-- Step 2: Clear all pending PIN reset OTPs (safe - these are temporary codes)
DELETE FROM pin_reset_otps WHERE id IS NOT NULL;

-- Step 3: Clear PIN-related security audit logs (optional - for clean slate)
-- This only removes PIN verification/change logs, not other security events
DELETE FROM security_audit_log 
WHERE action IN (
  'wallet_pin_verified',
  'wallet_pin_verified_edge',
  'wallet_pin_changed',
  'wallet_pin_set_via_otp',
  'wallet_pin_reset_edge',
  'pin_reset_otp_sent',
  'pin_reset_otp_verified'
);

-- Verification: These should return 0 after migration
-- SELECT COUNT(*) as users_with_pin FROM user_profiles WHERE wallet_pin_hash IS NOT NULL;
-- SELECT COUNT(*) as pending_otps FROM pin_reset_otps;