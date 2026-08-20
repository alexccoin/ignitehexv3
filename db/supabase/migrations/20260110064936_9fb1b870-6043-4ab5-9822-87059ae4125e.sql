
-- Fix wallet_setup_completed flag for users who have completed all security requirements
-- These users have: PIN set, recovery words set, and recovery words encrypted
-- But wallet_setup_completed is incorrectly set to false

UPDATE user_profiles
SET wallet_setup_completed = true
WHERE wallet_pin_hash IS NOT NULL
AND wallet_recovery_words IS NOT NULL
AND recovery_words_encrypted = true
AND wallet_setup_completed = false;
