-- Correct STR-shares for Albert Michael Resch from 6666 to 4444
UPDATE user_str_shares 
SET balance = 4444, updated_at = now()
WHERE user_id = '03af8061-c355-4bcc-b66f-936aba32c17d';

-- Deduct 13,333,333 STR tokens from staking pool
UPDATE user_staking_pools 
SET balance = balance - 13333333, updated_at = now()
WHERE user_id = '03af8061-c355-4bcc-b66f-936aba32c17d' AND pool_type = 'str';

-- Log the shares correction
INSERT INTO arss_transactions (user_id, amount, transaction_type, source_type, currency, description, status)
VALUES (
  '03af8061-c355-4bcc-b66f-936aba32c17d',
  -2222,
  'balance_correction',
  'admin_correction',
  'STR-Shares',
  'STR-Shares correction: 6666 → 4444 shares for Albert Michael Resch (duplicate entry removal)',
  'completed'
);

-- Log the tokens correction
INSERT INTO arss_transactions (user_id, amount, transaction_type, source_type, currency, description, status)
VALUES (
  '03af8061-c355-4bcc-b66f-936aba32c17d',
  -13333333,
  'balance_correction',
  'admin_correction',
  'wSTR',
  'STR tokens correction: deducted 13,333,333 STR for Albert Michael Resch (duplicate entry removal)',
  'completed'
);