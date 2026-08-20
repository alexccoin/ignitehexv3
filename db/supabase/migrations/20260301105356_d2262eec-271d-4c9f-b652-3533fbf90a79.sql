INSERT INTO guardian_invitations (invited_email, invited_by, status, expires_at)
VALUES (
  'jdwdubai@icloud.com',
  'bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b',
  'pending',
  now() + interval '30 days'
);