-- Add new values to the existing app_role enum
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'moderator' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'app_role')) THEN
        ALTER TYPE app_role ADD VALUE 'moderator';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'support' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'app_role')) THEN
        ALTER TYPE app_role ADD VALUE 'support';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'marketing' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'app_role')) THEN
        ALTER TYPE app_role ADD VALUE 'marketing';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'legal' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'app_role')) THEN
        ALTER TYPE app_role ADD VALUE 'legal';
    END IF;
END $$;

-- Create account status enum only if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'account_status') THEN
        CREATE TYPE account_status AS ENUM ('pending', 'approved', 'suspended', 'closed');
    END IF;
END $$;

-- Create user status enum only if it doesn't exist  
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_status') THEN
        CREATE TYPE user_status AS ENUM ('standard', 'silver', 'gold', 'platinum', 'vip');
    END IF;
END $$;

-- Add user_status column to user_profiles
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS user_status user_status DEFAULT 'standard';

-- Update the status column to use the enum (if it exists and is text)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'user_profiles' 
        AND column_name = 'status' 
        AND data_type = 'text'
    ) THEN
        ALTER TABLE user_profiles ALTER COLUMN status DROP DEFAULT;
        ALTER TABLE user_profiles ALTER COLUMN status TYPE account_status USING status::account_status;
        ALTER TABLE user_profiles ALTER COLUMN status SET DEFAULT 'pending';
    END IF;
END $$;