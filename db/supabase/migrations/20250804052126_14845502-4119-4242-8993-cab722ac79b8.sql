-- Recreate the cron job with proper schema reference for pg_net
SELECT cron.schedule(
  'daily-staking-rewards',
  '0 0 * * *', -- Every day at midnight UTC
  $$
  SELECT
    extensions.net.http_post(
        url:='https://lhkkfrpgbkjfcrodjslf.supabase.co/functions/v1/calculate-daily-rewards',
        headers:='{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imxoa2tmcnBnYmtqZmNyb2Rqc2xmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMwMDIyMjksImV4cCI6MjA2ODU3ODIyOX0.5cOx2njNOEO5kWJdI3rgmQ0B2Zttyp3e6kTdk2wdhsM"}'::jsonb,
        body:='{"automated": true}'::jsonb
    ) as request_id;
  $$
);