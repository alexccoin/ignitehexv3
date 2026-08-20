-- Correct STR-shares for user Wörz Geli (Zirius) from 2777 to 2730
UPDATE user_str_shares 
SET balance = 2730, updated_at = now()
WHERE user_id = 'f4d78a75-30fa-4e0e-8f85-ef7c8bbaf54f';

-- Log the correction
INSERT INTO arss_transactions (user_id, amount, transaction_type, source_type, currency, description, status)
VALUES (
  'f4d78a75-30fa-4e0e-8f85-ef7c8bbaf54f',
  -47,
  'balance_correction',
  'admin_correction',
  'STR-Shares',
  'STR-Shares correction: 2777 → 2730 shares for Wörz Geli (str.Zirius)',
  'completed'
);