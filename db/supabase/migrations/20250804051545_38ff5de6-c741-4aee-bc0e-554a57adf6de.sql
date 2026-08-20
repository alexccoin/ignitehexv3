-- Enable pg_cron extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Enable pg_net extension for HTTP requests if not already enabled  
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Remove any existing cron job with the same name
SELECT cron.unschedule('daily-staking-rewards');

-- Schedule the daily rewards calculation to run every day at midnight UTC
SELECT cron.schedule(
  'daily-staking-rewards',
  '0 0 * * *', -- Every day at midnight UTC
  $$
  SELECT
    net.http_post(
        url:='https://lhkkfrpgbkjfcrodjslf.supabase.co/functions/v1/calculate-daily-rewards',
        headers:='{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imxoa2tmcnBnYmtqZmNyb2Rqc2xmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMwMDIyMjksImV4cCI6MjA2ODU3ODIyOX0.5cOx2njNOEO5kWJdI3rgmQ0B2Zttyp3e6kTdk2wdhsM"}'::jsonb,
        body:='{"automated": true}'::jsonb
    ) as request_id;
  $$
);