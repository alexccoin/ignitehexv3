-- Revoke Thomas Wenz's Ares Guardian access
DO $$
DECLARE
  thomas_id UUID;
BEGIN
  SELECT id INTO thomas_id FROM auth.users WHERE email = 'thomas.wenz70@gmail.com' LIMIT 1;
  IF thomas_id IS NOT NULL THEN
    DELETE FROM public.guardian_wallets WHERE user_id = thomas_id;
    DELETE FROM public.guardian_invitations WHERE accepted_by = thomas_id OR invited_email = 'thomas.wenz70@gmail.com';
  ELSE
    DELETE FROM public.guardian_invitations WHERE invited_email = 'thomas.wenz70@gmail.com';
  END IF;
END $$;