-- Drop problematic trigger on prepaid_cards that references recovery_words_encrypted
DROP TRIGGER IF EXISTS audit_prepaid_cards ON prepaid_cards;