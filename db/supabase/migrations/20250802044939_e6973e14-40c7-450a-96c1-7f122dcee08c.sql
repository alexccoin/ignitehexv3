-- Ensure pgcrypto extension is enabled for user registration
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Also ensure other required extensions are available
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";