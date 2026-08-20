-- Enable the pgcrypto extension for cryptographic functions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Ensure the gen_random_uuid function is available (part of pgcrypto)
-- This is commonly used for generating UUIDs in default values