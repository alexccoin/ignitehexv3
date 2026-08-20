-- Enable required extensions for cron jobs
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Schedule the expired reservation cleanup to run every hour
SELECT cron.schedule(
  'release-expired-domain-reservations',
  '0 * * * *',
  $$
  SELECT
    net.http_post(
      url := 'https://lhkkfrpgbkjfcrodjslf.supabase.co/functions/v1/release-expired-reservations',
      headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imxoa2tmcnBnYmtqZmNyb2Rqc2xmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMwMDIyMjksImV4cCI6MjA2ODU3ODIyOX0.5cOx2njNOEO5kWJdI3rgmQ0B2Zttyp3e6kTdk2wdhsM"}'::jsonb,
      body := '{}'::jsonb
    ) AS request_id;
  $$
);