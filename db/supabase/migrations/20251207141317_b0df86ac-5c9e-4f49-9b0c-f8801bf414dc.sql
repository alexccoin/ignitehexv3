-- Find and drop the broken trigger that references recovery_words_encrypted
DROP TRIGGER IF EXISTS audit_sensitive_changes ON iban_accounts;
DROP TRIGGER IF EXISTS on_recovery_words_change ON iban_accounts;

-- Also check fiat_wallets table
DROP TRIGGER IF EXISTS audit_sensitive_changes ON fiat_wallets;
DROP TRIGGER IF EXISTS on_recovery_words_change ON fiat_wallets;