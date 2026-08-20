-- Move pgcrypto extension from public schema to extensions schema
DROP EXTENSION IF EXISTS pgcrypto CASCADE;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;