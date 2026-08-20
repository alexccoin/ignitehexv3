
UPDATE public.user_str_shares
SET balance = balance + 12500, updated_at = now()
WHERE user_id = 'f0186756-d1af-49ae-b3de-2b3094d6dd4d';

INSERT INTO public.arss_transactions (user_id, amount, transaction_type, source_type, currency, description, status)
VALUES ('f0186756-d1af-49ae-b3de-2b3094d6dd4d', 12500, 'manual_credit', 'private_seed_manual_shares_credit', 'STR-SHARES', 'Manual STR-Shares credit (Private Seed Admin): bonus', 'completed');

INSERT INTO public.private_seed_str_audit_log (application_id, user_id, action_type, action_details, performed_by)
VALUES (
  '195923c7-1a44-49de-8459-a3f826e0e242',
  'f0186756-d1af-49ae-b3de-2b3094d6dd4d',
  'manual_credit',
  jsonb_build_object('shares_amount', 12500, 'reason', 'bonus', 'user_email', 'schornstein.sarah@googlemail.com'),
  'f0186756-d1af-49ae-b3de-2b3094d6dd4d'
);
