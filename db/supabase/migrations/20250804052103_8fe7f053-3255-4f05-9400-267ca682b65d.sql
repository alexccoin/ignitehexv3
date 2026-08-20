-- Create extensions schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS extensions;

-- Drop the pg_net extension from public schema and reinstall in extensions schema
DROP EXTENSION IF EXISTS pg_net CASCADE;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Keep pg_cron in public schema but ensure it's properly installed
CREATE EXTENSION IF NOT EXISTS pg_cron;