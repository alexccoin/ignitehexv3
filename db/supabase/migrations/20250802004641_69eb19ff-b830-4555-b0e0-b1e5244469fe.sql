-- Enable pgcrypto extension which provides gen_random_bytes function
-- This is required for Supabase authentication to work properly
CREATE EXTENSION IF NOT EXISTS pgcrypto;