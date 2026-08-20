-- Enable required extensions for scheduling HTTP calls
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

-- Create private backups bucket
insert into storage.buckets (id, name, public)
values ('backups', 'backups', false)
on conflict (id) do nothing;

-- Storage policies: allow admins to read backups, system can write
create policy if not exists "Admins can read backups"
  on storage.objects for select
  using (
    bucket_id = 'backups' AND is_admin(auth.uid())
  );

-- Schedule daily backup at 03:00 UTC
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