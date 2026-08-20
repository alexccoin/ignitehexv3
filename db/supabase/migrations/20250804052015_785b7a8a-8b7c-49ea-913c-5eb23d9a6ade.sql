-- Create extensions schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS extensions;

-- Drop the extension from public schema
DROP EXTENSION IF EXISTS pg_net CASCADE;

-- Install pg_net extension in the extensions schema
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Also move pg_cron to extensions schema for consistency
DROP EXTENSION IF EXISTS pg_cron CASCADE;
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- Update the cron job to use the correct schema reference
SELECT cron.unschedule('daily-staking-rewards');

-- Recreate the cron job with proper schema reference
SELECT extensions.cron.schedule(
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