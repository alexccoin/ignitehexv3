-- Fix storage policy creation and ensure idempotency
-- Drop and recreate policy for storage backups
DROP POLICY IF EXISTS "Admins can read backups" ON storage.objects;
CREATE POLICY "Admins can read backups"
ON storage.objects
FOR SELECT
USING (
  bucket_id = 'backups' AND is_admin(auth.uid())
);

-- Ensure single cron schedule by unscheduling existing job if present
select cron.unschedule('daily-backup-0300utc') where exists (
  select 1 from cron.job where jobname = 'daily-backup-0300utc'
);

-- Recreate daily schedule at 03:00 UTC
select
  cron.schedule(
    'daily-backup-0300utc',
    '0 3 * * *',
    $$
    select
      net.http_post(
        url := 'https://lhkkfrpgbkjfcrodjslf.supabase.co/functions/v1/daily-backup',
        headers := '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imxoa2tmcnBnYmtqZmNyb2Rqc2xmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMwMDIyMjksImV4cCI6MjA2ODU3ODIyOX0.5cOx2njNOEO5kWJdI3rgmQ0B2Zttyp3e6kTdk2wdhsM"}'::jsonb,
        body := jsonb_build_object('triggered_at', now())
      ) as request_id;
    $$
  );