-- Recovered dashboard-created objects.
--
-- These tables and types exist in production but were never created by any
-- migration in this directory - they were made through the Lovable dashboard,
-- so the history references them without ever defining them. Reconstructed
-- from src/integrations/supabase/types.ts, which is generated from the live database.
--
-- Shapes are reconstructed, not dumped: later migrations in the history still
-- ALTER these tables, and those ALTERs are what bring them to final form.

-- Enum types
DO $$ BEGIN
  CREATE TYPE public.account_status AS ENUM ('pending', 'approved', 'suspended', 'closed');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  CREATE TYPE public.account_type_enum AS ENUM ('personal', 'business', 'corporate');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'moderator', 'user', 'support', 'marketing', 'legal', 'arx', 'seed_str_admin');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  CREATE TYPE public.pool_status AS ENUM ('active', 'paused', 'closed', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  CREATE TYPE public.reward_curve AS ENUM ('linear', 'tiered', 'exponential');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  CREATE TYPE public.user_status AS ENUM ('standard', 'silver', 'gold', 'platinum', 'vip');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Tables
CREATE TABLE IF NOT EXISTS public.ai_usage_sessions (
  "compute_cost" numeric(18,8) DEFAULT 0 NOT NULL,
  "duration_seconds" integer DEFAULT 0,
  "ended_at" timestamp with time zone,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "session_type" text NOT NULL,
  "started_at" timestamp with time zone DEFAULT now() NOT NULL,
  "status" text DEFAULT 'active'::text NOT NULL,
  "tokens_used" numeric(18,8) DEFAULT 0 NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT ai_usage_sessions_pkey PRIMARY KEY (id)
);
ALTER TABLE public.ai_usage_sessions ADD COLUMN IF NOT EXISTS "compute_cost" numeric(18,8) DEFAULT 0;
ALTER TABLE public.ai_usage_sessions ADD COLUMN IF NOT EXISTS "duration_seconds" integer DEFAULT 0;
ALTER TABLE public.ai_usage_sessions ADD COLUMN IF NOT EXISTS "ended_at" timestamp with time zone;
ALTER TABLE public.ai_usage_sessions ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.ai_usage_sessions ADD COLUMN IF NOT EXISTS "session_type" text;
ALTER TABLE public.ai_usage_sessions ADD COLUMN IF NOT EXISTS "started_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.ai_usage_sessions ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'active'::text;
ALTER TABLE public.ai_usage_sessions ADD COLUMN IF NOT EXISTS "tokens_used" numeric(18,8) DEFAULT 0;
ALTER TABLE public.ai_usage_sessions ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.capacity_sharing (
  "capacity_amount" numeric(10,2) NOT NULL,
  "capacity_unit" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "hourly_rate" numeric(18,8) NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "sharing_type" text NOT NULL,
  "status" text DEFAULT 'available'::text NOT NULL,
  "total_earned" numeric(18,8) DEFAULT 0,
  "total_hours_shared" numeric(10,2) DEFAULT 0,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT capacity_sharing_pkey PRIMARY KEY (id)
);
ALTER TABLE public.capacity_sharing ADD COLUMN IF NOT EXISTS "capacity_amount" numeric(10,2);
ALTER TABLE public.capacity_sharing ADD COLUMN IF NOT EXISTS "capacity_unit" text;
ALTER TABLE public.capacity_sharing ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.capacity_sharing ADD COLUMN IF NOT EXISTS "hourly_rate" numeric(18,8);
ALTER TABLE public.capacity_sharing ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.capacity_sharing ADD COLUMN IF NOT EXISTS "sharing_type" text;
ALTER TABLE public.capacity_sharing ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'available'::text;
ALTER TABLE public.capacity_sharing ADD COLUMN IF NOT EXISTS "total_earned" numeric(18,8) DEFAULT 0;
ALTER TABLE public.capacity_sharing ADD COLUMN IF NOT EXISTS "total_hours_shared" numeric(10,2) DEFAULT 0;
ALTER TABLE public.capacity_sharing ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.capacity_sharing ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.learning_contributions (
  "arss_reward" numeric(18,8) DEFAULT 0,
  "content_text" text,
  "content_url" text,
  "contribution_type" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "description" text,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "processed_at" timestamp with time zone,
  "quality_score" integer DEFAULT 0,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "tags" text[],
  "title" text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT learning_contributions_pkey PRIMARY KEY (id)
);
ALTER TABLE public.learning_contributions ADD COLUMN IF NOT EXISTS "arss_reward" numeric(18,8) DEFAULT 0;
ALTER TABLE public.learning_contributions ADD COLUMN IF NOT EXISTS "content_text" text;
ALTER TABLE public.learning_contributions ADD COLUMN IF NOT EXISTS "content_url" text;
ALTER TABLE public.learning_contributions ADD COLUMN IF NOT EXISTS "contribution_type" text;
ALTER TABLE public.learning_contributions ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.learning_contributions ADD COLUMN IF NOT EXISTS "description" text;
ALTER TABLE public.learning_contributions ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.learning_contributions ADD COLUMN IF NOT EXISTS "processed_at" timestamp with time zone;
ALTER TABLE public.learning_contributions ADD COLUMN IF NOT EXISTS "quality_score" integer DEFAULT 0;
ALTER TABLE public.learning_contributions ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.learning_contributions ADD COLUMN IF NOT EXISTS "tags" text[];
ALTER TABLE public.learning_contributions ADD COLUMN IF NOT EXISTS "title" text;
ALTER TABLE public.learning_contributions ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.learning_contributions ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.pending_balance_locks (
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "expires_at" timestamp with time zone DEFAULT (now() + '00:05:00'::interval) NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "locked_amount" numeric NOT NULL,
  "token_type" text NOT NULL,
  "transaction_id" uuid NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT pending_balance_locks_pkey PRIMARY KEY (id)
);
ALTER TABLE public.pending_balance_locks ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.pending_balance_locks ADD COLUMN IF NOT EXISTS "expires_at" timestamp with time zone DEFAULT (now() + '00:05:00'::interval);
ALTER TABLE public.pending_balance_locks ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.pending_balance_locks ADD COLUMN IF NOT EXISTS "locked_amount" numeric;
ALTER TABLE public.pending_balance_locks ADD COLUMN IF NOT EXISTS "token_type" text;
ALTER TABLE public.pending_balance_locks ADD COLUMN IF NOT EXISTS "transaction_id" uuid;
ALTER TABLE public.pending_balance_locks ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.str_domain_connections (
  "api_key" text,
  "connection_status" text DEFAULT 'pending'::text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "domain_name" text NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "last_sync" timestamp with time zone,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT str_domain_connections_pkey PRIMARY KEY (id)
);
ALTER TABLE public.str_domain_connections ADD COLUMN IF NOT EXISTS "api_key" text;
ALTER TABLE public.str_domain_connections ADD COLUMN IF NOT EXISTS "connection_status" text DEFAULT 'pending'::text;
ALTER TABLE public.str_domain_connections ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.str_domain_connections ADD COLUMN IF NOT EXISTS "domain_name" text;
ALTER TABLE public.str_domain_connections ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.str_domain_connections ADD COLUMN IF NOT EXISTS "last_sync" timestamp with time zone;
ALTER TABLE public.str_domain_connections ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.str_domain_connections ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.airdrop_registrations (
  "admin_notes" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "credited_amount" numeric DEFAULT 0,
  "credited_at" timestamp with time zone,
  "email_address" text NOT NULL,
  "event_type" text,
  "full_name" text NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "processed_at" timestamp with time zone,
  "processed_by" uuid,
  "requested_amount" numeric DEFAULT 1000 NOT NULL,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "tokens_credited" boolean DEFAULT false,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  "voucher_id" uuid,
  "voucher_type" text,
  "wallet_address" text NOT NULL,
  CONSTRAINT airdrop_registrations_pkey PRIMARY KEY (id)
);
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "admin_notes" text;
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "credited_amount" numeric DEFAULT 0;
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "credited_at" timestamp with time zone;
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "email_address" text;
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "event_type" text;
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "full_name" text;
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "processed_at" timestamp with time zone;
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "processed_by" uuid;
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "requested_amount" numeric DEFAULT 1000;
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "tokens_credited" boolean DEFAULT false;
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "user_id" uuid;
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "voucher_id" uuid;
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "voucher_type" text;
ALTER TABLE public.airdrop_registrations ADD COLUMN IF NOT EXISTS "wallet_address" text;
CREATE TABLE IF NOT EXISTS public.arss_transactions (
  "amount" numeric(18,8) NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "currency" text DEFAULT 'wSTR'::text,
  "description" text NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "source_id" uuid,
  "source_type" text NOT NULL,
  "status" text DEFAULT 'completed'::text NOT NULL,
  "transaction_hash" text,
  "transaction_type" text NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT arss_transactions_pkey PRIMARY KEY (id)
);
ALTER TABLE public.arss_transactions ADD COLUMN IF NOT EXISTS "amount" numeric(18,8);
ALTER TABLE public.arss_transactions ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.arss_transactions ADD COLUMN IF NOT EXISTS "currency" text DEFAULT 'wSTR'::text;
ALTER TABLE public.arss_transactions ADD COLUMN IF NOT EXISTS "description" text;
ALTER TABLE public.arss_transactions ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.arss_transactions ADD COLUMN IF NOT EXISTS "source_id" uuid;
ALTER TABLE public.arss_transactions ADD COLUMN IF NOT EXISTS "source_type" text;
ALTER TABLE public.arss_transactions ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'completed'::text;
ALTER TABLE public.arss_transactions ADD COLUMN IF NOT EXISTS "transaction_hash" text;
ALTER TABLE public.arss_transactions ADD COLUMN IF NOT EXISTS "transaction_type" text;
ALTER TABLE public.arss_transactions ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.arx_audit_trail (
  "action_type" text NOT NULL,
  "attestation_hash" text,
  "changes" jsonb DEFAULT '{}'::jsonb,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "ip_address" inet,
  "performed_by" uuid NOT NULL,
  "resource_id" text NOT NULL,
  "resource_type" text NOT NULL,
  "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
  "user_agent" text,
  CONSTRAINT arx_audit_trail_pkey PRIMARY KEY (id)
);
ALTER TABLE public.arx_audit_trail ADD COLUMN IF NOT EXISTS "action_type" text;
ALTER TABLE public.arx_audit_trail ADD COLUMN IF NOT EXISTS "attestation_hash" text;
ALTER TABLE public.arx_audit_trail ADD COLUMN IF NOT EXISTS "changes" jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.arx_audit_trail ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.arx_audit_trail ADD COLUMN IF NOT EXISTS "ip_address" inet;
ALTER TABLE public.arx_audit_trail ADD COLUMN IF NOT EXISTS "performed_by" uuid;
ALTER TABLE public.arx_audit_trail ADD COLUMN IF NOT EXISTS "resource_id" text;
ALTER TABLE public.arx_audit_trail ADD COLUMN IF NOT EXISTS "resource_type" text;
ALTER TABLE public.arx_audit_trail ADD COLUMN IF NOT EXISTS "timestamp" timestamp with time zone DEFAULT now();
ALTER TABLE public.arx_audit_trail ADD COLUMN IF NOT EXISTS "user_agent" text;
CREATE TABLE IF NOT EXISTS public.arx_club_members (
  "activation_hash" text,
  "benefits" jsonb DEFAULT '{}'::jsonb,
  "council_member" boolean DEFAULT false,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "executive_board" boolean DEFAULT false,
  "expires_at" timestamp with time zone,
  "governance_role" text DEFAULT 'member'::text,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "joined_at" timestamp with time zone DEFAULT now() NOT NULL,
  "kyc_status" text DEFAULT 'pending'::text,
  "kyc_verified_at" timestamp with time zone,
  "membership_tier" text DEFAULT 'standard'::text NOT NULL,
  "metadata" jsonb DEFAULT '{}'::jsonb,
  "node_operator" boolean DEFAULT false,
  "status" text DEFAULT 'active'::text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  "voting_weight" integer DEFAULT 1,
  "wnft_credential" text,
  CONSTRAINT arx_club_members_pkey PRIMARY KEY (id)
);
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "activation_hash" text;
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "benefits" jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "council_member" boolean DEFAULT false;
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "executive_board" boolean DEFAULT false;
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "expires_at" timestamp with time zone;
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "governance_role" text DEFAULT 'member'::text;
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "joined_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "kyc_status" text DEFAULT 'pending'::text;
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "kyc_verified_at" timestamp with time zone;
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "membership_tier" text DEFAULT 'standard'::text;
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "metadata" jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "node_operator" boolean DEFAULT false;
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'active'::text;
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "user_id" uuid;
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "voting_weight" integer DEFAULT 1;
ALTER TABLE public.arx_club_members ADD COLUMN IF NOT EXISTS "wnft_credential" text;
CREATE TABLE IF NOT EXISTS public.arx_treasury_transactions (
  "amount" numeric NOT NULL,
  "attestation_hash" text,
  "collected_signatures" jsonb DEFAULT '[]'::jsonb,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "currency" text NOT NULL,
  "executed_at" timestamp with time zone,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "initiated_by" uuid NOT NULL,
  "metadata" jsonb DEFAULT '{}'::jsonb,
  "multisig_approval_hash" text,
  "oracle_rate" numeric,
  "pool_id" uuid NOT NULL,
  "required_signatures" integer NOT NULL,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "transaction_type" text NOT NULL,
  "usd_equivalent" numeric,
  CONSTRAINT arx_treasury_transactions_pkey PRIMARY KEY (id)
);
ALTER TABLE public.arx_treasury_transactions ADD COLUMN IF NOT EXISTS "amount" numeric;
ALTER TABLE public.arx_treasury_transactions ADD COLUMN IF NOT EXISTS "attestation_hash" text;
ALTER TABLE public.arx_treasury_transactions ADD COLUMN IF NOT EXISTS "collected_signatures" jsonb DEFAULT '[]'::jsonb;
ALTER TABLE public.arx_treasury_transactions ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.arx_treasury_transactions ADD COLUMN IF NOT EXISTS "currency" text;
ALTER TABLE public.arx_treasury_transactions ADD COLUMN IF NOT EXISTS "executed_at" timestamp with time zone;
ALTER TABLE public.arx_treasury_transactions ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.arx_treasury_transactions ADD COLUMN IF NOT EXISTS "initiated_by" uuid;
ALTER TABLE public.arx_treasury_transactions ADD COLUMN IF NOT EXISTS "metadata" jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.arx_treasury_transactions ADD COLUMN IF NOT EXISTS "multisig_approval_hash" text;
ALTER TABLE public.arx_treasury_transactions ADD COLUMN IF NOT EXISTS "oracle_rate" numeric;
ALTER TABLE public.arx_treasury_transactions ADD COLUMN IF NOT EXISTS "pool_id" uuid;
ALTER TABLE public.arx_treasury_transactions ADD COLUMN IF NOT EXISTS "required_signatures" integer;
ALTER TABLE public.arx_treasury_transactions ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.arx_treasury_transactions ADD COLUMN IF NOT EXISTS "transaction_type" text;
ALTER TABLE public.arx_treasury_transactions ADD COLUMN IF NOT EXISTS "usd_equivalent" numeric;
CREATE TABLE IF NOT EXISTS public.auth_attempts (
  "additional_data" jsonb,
  "attempt_type" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now(),
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "ip_address" inet,
  "success" boolean DEFAULT false NOT NULL,
  "user_agent" text,
  "user_id" uuid,
  CONSTRAINT auth_attempts_pkey PRIMARY KEY (id)
);
ALTER TABLE public.auth_attempts ADD COLUMN IF NOT EXISTS "additional_data" jsonb;
ALTER TABLE public.auth_attempts ADD COLUMN IF NOT EXISTS "attempt_type" text;
ALTER TABLE public.auth_attempts ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.auth_attempts ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.auth_attempts ADD COLUMN IF NOT EXISTS "ip_address" inet;
ALTER TABLE public.auth_attempts ADD COLUMN IF NOT EXISTS "success" boolean DEFAULT false;
ALTER TABLE public.auth_attempts ADD COLUMN IF NOT EXISTS "user_agent" text;
ALTER TABLE public.auth_attempts ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.ccoin_bank_applications (
  "account_type" text DEFAULT 'personal'::text,
  "admin_notes" text,
  "application_metadata" jsonb DEFAULT '{}'::jsonb,
  "company_name" text,
  "company_registration_number" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "email" text NOT NULL,
  "full_name" text NOT NULL,
  "gdpr_accepted" boolean DEFAULT false NOT NULL,
  "gdpr_accepted_at" timestamp with time zone,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "ip_address" inet,
  "nda_accepted" boolean DEFAULT false NOT NULL,
  "nda_accepted_at" timestamp with time zone,
  "processed_at" timestamp with time zone,
  "processed_by" uuid,
  "requested_products" jsonb DEFAULT '{"iban_chf": false, "iban_eur": false, "iban_gbp": false, "visa_card": false, "ccoin_card": false}'::jsonb,
  "signature_date" timestamp with time zone DEFAULT now() NOT NULL,
  "signature_full_name" text NOT NULL,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "terms_accepted" boolean DEFAULT false NOT NULL,
  "terms_accepted_at" timestamp with time zone,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_agent" text,
  "user_id" uuid NOT NULL,
  CONSTRAINT ccoin_bank_applications_pkey PRIMARY KEY (id)
);
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "account_type" text DEFAULT 'personal'::text;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "admin_notes" text;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "application_metadata" jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "company_name" text;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "company_registration_number" text;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "email" text;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "full_name" text;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "gdpr_accepted" boolean DEFAULT false;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "gdpr_accepted_at" timestamp with time zone;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "ip_address" inet;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "nda_accepted" boolean DEFAULT false;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "nda_accepted_at" timestamp with time zone;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "processed_at" timestamp with time zone;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "processed_by" uuid;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "requested_products" jsonb DEFAULT '{"iban_chf": false, "iban_eur": false, "iban_gbp": false, "visa_card": false, "ccoin_card": false}'::jsonb;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "signature_date" timestamp with time zone DEFAULT now();
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "signature_full_name" text;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "terms_accepted" boolean DEFAULT false;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "terms_accepted_at" timestamp with time zone;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "user_agent" text;
ALTER TABLE public.ccoin_bank_applications ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.ccoin_banking_profiles (
  "account_type" text DEFAULT 'personal'::text,
  "authorized_signatories" jsonb DEFAULT '[]'::jsonb,
  "banking_status" text DEFAULT 'active'::text,
  "business_address" jsonb,
  "business_type" text,
  "card_networks_enabled" text[] DEFAULT ARRAY['ccoin'::text, 'visa'::text],
  "ccoin_card_created" boolean DEFAULT false,
  "ccoin_card_id" uuid,
  "chf_iban_created" boolean DEFAULT false,
  "chf_iban_id" uuid,
  "company_name" text,
  "company_registration_number" text,
  "corporate_structure" jsonb,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "default_iban_country" text DEFAULT 'CH'::text,
  "email_address" text NOT NULL,
  "eur_iban_created" boolean DEFAULT false,
  "eur_iban_id" uuid,
  "full_name" text NOT NULL,
  "gbp_iban_created" boolean DEFAULT false,
  "gbp_iban_id" uuid,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "kyc_status" text DEFAULT 'pending'::text,
  "last_banking_sync" timestamp with time zone,
  "preferred_iban_currencies" text[] DEFAULT ARRAY['EUR'::text, 'CHF'::text, 'GBP'::text],
  "str_domain" text,
  "str_wallet_address" text,
  "tax_id" text,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  "visa_card_created" boolean DEFAULT false,
  "visa_card_id" uuid,
  CONSTRAINT ccoin_banking_profiles_pkey PRIMARY KEY (id)
);
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "account_type" text DEFAULT 'personal'::text;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "authorized_signatories" jsonb DEFAULT '[]'::jsonb;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "banking_status" text DEFAULT 'active'::text;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "business_address" jsonb;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "business_type" text;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "card_networks_enabled" text[] DEFAULT ARRAY['ccoin'::text, 'visa'::text];
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "ccoin_card_created" boolean DEFAULT false;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "ccoin_card_id" uuid;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "chf_iban_created" boolean DEFAULT false;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "chf_iban_id" uuid;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "company_name" text;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "company_registration_number" text;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "corporate_structure" jsonb;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "default_iban_country" text DEFAULT 'CH'::text;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "email_address" text;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "eur_iban_created" boolean DEFAULT false;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "eur_iban_id" uuid;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "full_name" text;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "gbp_iban_created" boolean DEFAULT false;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "gbp_iban_id" uuid;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "kyc_status" text DEFAULT 'pending'::text;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "last_banking_sync" timestamp with time zone;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "preferred_iban_currencies" text[] DEFAULT ARRAY['EUR'::text, 'CHF'::text, 'GBP'::text];
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "str_domain" text;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "str_wallet_address" text;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "tax_id" text;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "user_id" uuid;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "visa_card_created" boolean DEFAULT false;
ALTER TABLE public.ccoin_banking_profiles ADD COLUMN IF NOT EXISTS "visa_card_id" uuid;
CREATE TABLE IF NOT EXISTS public.ccoin_validations (
  "card_identifier" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "details" jsonb,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "result" text NOT NULL,
  "user_id" uuid,
  CONSTRAINT ccoin_validations_pkey PRIMARY KEY (id)
);
ALTER TABLE public.ccoin_validations ADD COLUMN IF NOT EXISTS "card_identifier" text;
ALTER TABLE public.ccoin_validations ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.ccoin_validations ADD COLUMN IF NOT EXISTS "details" jsonb;
ALTER TABLE public.ccoin_validations ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.ccoin_validations ADD COLUMN IF NOT EXISTS "result" text;
ALTER TABLE public.ccoin_validations ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.crypto_wallets (
  "available_balance" numeric DEFAULT 0 NOT NULL,
  "balance" numeric DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "held_balance" numeric DEFAULT 0 NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "token_type" text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT crypto_wallets_pkey PRIMARY KEY (id)
);
ALTER TABLE public.crypto_wallets ADD COLUMN IF NOT EXISTS "available_balance" numeric DEFAULT 0;
ALTER TABLE public.crypto_wallets ADD COLUMN IF NOT EXISTS "balance" numeric DEFAULT 0;
ALTER TABLE public.crypto_wallets ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.crypto_wallets ADD COLUMN IF NOT EXISTS "held_balance" numeric DEFAULT 0;
ALTER TABLE public.crypto_wallets ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.crypto_wallets ADD COLUMN IF NOT EXISTS "token_type" text;
ALTER TABLE public.crypto_wallets ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.crypto_wallets ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.currency_exchanges (
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "exchange_rate" numeric NOT NULL,
  "fee_amount" numeric DEFAULT 0 NOT NULL,
  "fee_ccos" numeric DEFAULT 0 NOT NULL,
  "fee_ledger_id" uuid,
  "from_amount" numeric NOT NULL,
  "from_currency" text NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "rail" text,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "to_amount" numeric NOT NULL,
  "to_currency" text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT currency_exchanges_pkey PRIMARY KEY (id)
);
ALTER TABLE public.currency_exchanges ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.currency_exchanges ADD COLUMN IF NOT EXISTS "exchange_rate" numeric;
ALTER TABLE public.currency_exchanges ADD COLUMN IF NOT EXISTS "fee_amount" numeric DEFAULT 0;
ALTER TABLE public.currency_exchanges ADD COLUMN IF NOT EXISTS "fee_ccos" numeric DEFAULT 0;
ALTER TABLE public.currency_exchanges ADD COLUMN IF NOT EXISTS "fee_ledger_id" uuid;
ALTER TABLE public.currency_exchanges ADD COLUMN IF NOT EXISTS "from_amount" numeric;
ALTER TABLE public.currency_exchanges ADD COLUMN IF NOT EXISTS "from_currency" text;
ALTER TABLE public.currency_exchanges ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.currency_exchanges ADD COLUMN IF NOT EXISTS "rail" text;
ALTER TABLE public.currency_exchanges ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.currency_exchanges ADD COLUMN IF NOT EXISTS "to_amount" numeric;
ALTER TABLE public.currency_exchanges ADD COLUMN IF NOT EXISTS "to_currency" text;
ALTER TABLE public.currency_exchanges ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.currency_exchanges ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.domain_marketplace_bids (
  "bid_amount" numeric NOT NULL,
  "bidder_id" uuid NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "currency" text DEFAULT 'USD'::text NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "is_winning_bid" boolean DEFAULT false,
  "listing_id" uuid NOT NULL,
  "status" text DEFAULT 'pending'::text NOT NULL,
  CONSTRAINT domain_marketplace_bids_pkey PRIMARY KEY (id)
);
ALTER TABLE public.domain_marketplace_bids ADD COLUMN IF NOT EXISTS "bid_amount" numeric;
ALTER TABLE public.domain_marketplace_bids ADD COLUMN IF NOT EXISTS "bidder_id" uuid;
ALTER TABLE public.domain_marketplace_bids ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.domain_marketplace_bids ADD COLUMN IF NOT EXISTS "currency" text DEFAULT 'USD'::text;
ALTER TABLE public.domain_marketplace_bids ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.domain_marketplace_bids ADD COLUMN IF NOT EXISTS "is_winning_bid" boolean DEFAULT false;
ALTER TABLE public.domain_marketplace_bids ADD COLUMN IF NOT EXISTS "listing_id" uuid;
ALTER TABLE public.domain_marketplace_bids ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
CREATE TABLE IF NOT EXISTS public.domain_marketplace_listings (
  "accepted_bid_id" uuid,
  "auction_end_at" timestamp with time zone,
  "buy_now_price" numeric,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "currency" text DEFAULT 'USD'::text NOT NULL,
  "current_bid" numeric,
  "current_bidder_id" uuid,
  "description" text,
  "domain_id" uuid,
  "domain_name" text NOT NULL,
  "domain_type" text NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "is_admin_listing" boolean DEFAULT false,
  "listing_type" text NOT NULL,
  "reservation_expires_at" timestamp with time zone,
  "reserve_price" numeric,
  "reserved_at" timestamp with time zone,
  "reserved_by" uuid,
  "seller_eth_wallet" text,
  "seller_id" uuid NOT NULL,
  "seller_wallet_address" text,
  "seller_wallet_currency" text,
  "starting_bid" numeric,
  "status" text DEFAULT 'active'::text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "views_count" integer DEFAULT 0,
  "category" text,
  "image_url" text,
  CONSTRAINT domain_marketplace_listings_pkey PRIMARY KEY (id)
);
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "accepted_bid_id" uuid;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "auction_end_at" timestamp with time zone;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "buy_now_price" numeric;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "currency" text DEFAULT 'USD'::text;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "current_bid" numeric;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "current_bidder_id" uuid;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "description" text;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "domain_id" uuid;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "domain_name" text;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "domain_type" text;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "is_admin_listing" boolean DEFAULT false;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "listing_type" text;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "reservation_expires_at" timestamp with time zone;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "reserve_price" numeric;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "reserved_at" timestamp with time zone;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "reserved_by" uuid;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "seller_eth_wallet" text;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "seller_id" uuid;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "seller_wallet_address" text;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "seller_wallet_currency" text;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "starting_bid" numeric;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'active'::text;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "views_count" integer DEFAULT 0;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "category" text;
ALTER TABLE public.domain_marketplace_listings ADD COLUMN IF NOT EXISTS "image_url" text;
CREATE TABLE IF NOT EXISTS public.domain_marketplace_transactions (
  "admin_approved_at" timestamp with time zone,
  "admin_approved_by" uuid,
  "admin_notes" text,
  "buyer_id" uuid NOT NULL,
  "buyer_wallet_address" text,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "currency" text DEFAULT 'USD'::text NOT NULL,
  "domain_id" uuid,
  "escrow_status" text DEFAULT 'pending'::text NOT NULL,
  "expires_at" timestamp with time zone,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "listing_id" uuid,
  "payment_proof_url" text,
  "released_at" timestamp with time zone,
  "sale_price" numeric NOT NULL,
  "sale_type" text NOT NULL,
  "seller_id" uuid NOT NULL,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "transaction_fee" numeric DEFAULT 0,
  "transaction_hash" text,
  CONSTRAINT domain_marketplace_transactions_pkey PRIMARY KEY (id)
);
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "admin_approved_at" timestamp with time zone;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "admin_approved_by" uuid;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "admin_notes" text;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "buyer_id" uuid;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "buyer_wallet_address" text;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "completed_at" timestamp with time zone;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "currency" text DEFAULT 'USD'::text;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "domain_id" uuid;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "escrow_status" text DEFAULT 'pending'::text;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "expires_at" timestamp with time zone;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "listing_id" uuid;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "payment_proof_url" text;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "released_at" timestamp with time zone;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "sale_price" numeric;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "sale_type" text;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "seller_id" uuid;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "transaction_fee" numeric DEFAULT 0;
ALTER TABLE public.domain_marketplace_transactions ADD COLUMN IF NOT EXISTS "transaction_hash" text;
CREATE TABLE IF NOT EXISTS public.enhanced_rate_limits (
  "attempts" integer DEFAULT 1 NOT NULL,
  "blocked_until" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "identifier" text NOT NULL,
  "last_attempt" timestamp with time zone DEFAULT now() NOT NULL,
  "operation_type" text NOT NULL,
  "window_start" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT enhanced_rate_limits_pkey PRIMARY KEY (id)
);
ALTER TABLE public.enhanced_rate_limits ADD COLUMN IF NOT EXISTS "attempts" integer DEFAULT 1;
ALTER TABLE public.enhanced_rate_limits ADD COLUMN IF NOT EXISTS "blocked_until" timestamp with time zone;
ALTER TABLE public.enhanced_rate_limits ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.enhanced_rate_limits ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.enhanced_rate_limits ADD COLUMN IF NOT EXISTS "identifier" text;
ALTER TABLE public.enhanced_rate_limits ADD COLUMN IF NOT EXISTS "last_attempt" timestamp with time zone DEFAULT now();
ALTER TABLE public.enhanced_rate_limits ADD COLUMN IF NOT EXISTS "operation_type" text;
ALTER TABLE public.enhanced_rate_limits ADD COLUMN IF NOT EXISTS "window_start" timestamp with time zone DEFAULT now();
CREATE TABLE IF NOT EXISTS public.enhanced_staking_pools (
  "apr_max" numeric(5,2) NOT NULL,
  "apr_min" numeric(5,2) NOT NULL,
  "compounding" boolean DEFAULT false,
  "created_at" timestamp with time zone DEFAULT now(),
  "description" text,
  "duration_months" integer NOT NULL,
  "end_date" timestamp with time zone,
  "icon" text DEFAULT 'zap'::text,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "max_stake_amount" numeric DEFAULT 10000000,
  "min_stake_amount" numeric DEFAULT 1000,
  "name" text NOT NULL,
  "reward_curve" public.reward_curve DEFAULT 'linear'::reward_curve,
  "start_date" timestamp with time zone DEFAULT now(),
  "status" public.pool_status DEFAULT 'active'::pool_status,
  "theme" text NOT NULL,
  "token_type" text DEFAULT 'str'::text NOT NULL,
  "tvl_cap" numeric,
  "updated_at" timestamp with time zone DEFAULT now(),
  "whitelist_only" boolean DEFAULT false,
  CONSTRAINT enhanced_staking_pools_pkey PRIMARY KEY (id)
);
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "apr_max" numeric(5,2);
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "apr_min" numeric(5,2);
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "compounding" boolean DEFAULT false;
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "description" text;
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "duration_months" integer;
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "end_date" timestamp with time zone;
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "icon" text DEFAULT 'zap'::text;
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "max_stake_amount" numeric DEFAULT 10000000;
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "min_stake_amount" numeric DEFAULT 1000;
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "name" text;
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "reward_curve" public.reward_curve DEFAULT 'linear'::reward_curve;
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "start_date" timestamp with time zone DEFAULT now();
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "status" public.pool_status DEFAULT 'active'::pool_status;
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "theme" text;
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "token_type" text DEFAULT 'str'::text;
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "tvl_cap" numeric;
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.enhanced_staking_pools ADD COLUMN IF NOT EXISTS "whitelist_only" boolean DEFAULT false;
CREATE TABLE IF NOT EXISTS public.fiat_transactions (
  "amount" numeric NOT NULL,
  "approved_at" timestamp with time zone,
  "approved_by" uuid,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "currency" text NOT NULL,
  "fee" numeric DEFAULT 0 NOT NULL,
  "from_identifier" text NOT NULL,
  "from_user_id" uuid NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "metadata" jsonb DEFAULT '{}'::jsonb,
  "requires_approval" boolean DEFAULT false NOT NULL,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "to_identifier" text NOT NULL,
  "to_user_id" uuid,
  "transfer_type" text NOT NULL,
  "tx_id" text NOT NULL,
  CONSTRAINT fiat_transactions_pkey PRIMARY KEY (id)
);
ALTER TABLE public.fiat_transactions ADD COLUMN IF NOT EXISTS "amount" numeric;
ALTER TABLE public.fiat_transactions ADD COLUMN IF NOT EXISTS "approved_at" timestamp with time zone;
ALTER TABLE public.fiat_transactions ADD COLUMN IF NOT EXISTS "approved_by" uuid;
ALTER TABLE public.fiat_transactions ADD COLUMN IF NOT EXISTS "completed_at" timestamp with time zone;
ALTER TABLE public.fiat_transactions ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.fiat_transactions ADD COLUMN IF NOT EXISTS "currency" text;
ALTER TABLE public.fiat_transactions ADD COLUMN IF NOT EXISTS "fee" numeric DEFAULT 0;
ALTER TABLE public.fiat_transactions ADD COLUMN IF NOT EXISTS "from_identifier" text;
ALTER TABLE public.fiat_transactions ADD COLUMN IF NOT EXISTS "from_user_id" uuid;
ALTER TABLE public.fiat_transactions ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.fiat_transactions ADD COLUMN IF NOT EXISTS "metadata" jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.fiat_transactions ADD COLUMN IF NOT EXISTS "requires_approval" boolean DEFAULT false;
ALTER TABLE public.fiat_transactions ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.fiat_transactions ADD COLUMN IF NOT EXISTS "to_identifier" text;
ALTER TABLE public.fiat_transactions ADD COLUMN IF NOT EXISTS "to_user_id" uuid;
ALTER TABLE public.fiat_transactions ADD COLUMN IF NOT EXISTS "transfer_type" text;
ALTER TABLE public.fiat_transactions ADD COLUMN IF NOT EXISTS "tx_id" text;
CREATE TABLE IF NOT EXISTS public.fiat_wallets (
  "available_balance" numeric DEFAULT 0 NOT NULL,
  "balance" numeric DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "currency" text NOT NULL,
  "held_balance" numeric DEFAULT 0 NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT fiat_wallets_pkey PRIMARY KEY (id)
);
ALTER TABLE public.fiat_wallets ADD COLUMN IF NOT EXISTS "available_balance" numeric DEFAULT 0;
ALTER TABLE public.fiat_wallets ADD COLUMN IF NOT EXISTS "balance" numeric DEFAULT 0;
ALTER TABLE public.fiat_wallets ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.fiat_wallets ADD COLUMN IF NOT EXISTS "currency" text;
ALTER TABLE public.fiat_wallets ADD COLUMN IF NOT EXISTS "held_balance" numeric DEFAULT 0;
ALTER TABLE public.fiat_wallets ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.fiat_wallets ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.fiat_wallets ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.github_integrations (
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "encrypted_access_token" text,
  "encryption_version" integer DEFAULT 0,
  "github_username" text NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "integration_status" text DEFAULT 'active'::text NOT NULL,
  "is_token_encrypted" boolean DEFAULT true,
  "last_sync" timestamp with time zone,
  "repo_count" integer DEFAULT 0,
  "token_encryption_iv" text,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  "access_token" text /* legacy: referenced by migration history */,
  CONSTRAINT github_integrations_pkey PRIMARY KEY (id)
);
ALTER TABLE public.github_integrations ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.github_integrations ADD COLUMN IF NOT EXISTS "encrypted_access_token" text;
ALTER TABLE public.github_integrations ADD COLUMN IF NOT EXISTS "encryption_version" integer DEFAULT 0;
ALTER TABLE public.github_integrations ADD COLUMN IF NOT EXISTS "github_username" text;
ALTER TABLE public.github_integrations ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.github_integrations ADD COLUMN IF NOT EXISTS "integration_status" text DEFAULT 'active'::text;
ALTER TABLE public.github_integrations ADD COLUMN IF NOT EXISTS "is_token_encrypted" boolean DEFAULT true;
ALTER TABLE public.github_integrations ADD COLUMN IF NOT EXISTS "last_sync" timestamp with time zone;
ALTER TABLE public.github_integrations ADD COLUMN IF NOT EXISTS "repo_count" integer DEFAULT 0;
ALTER TABLE public.github_integrations ADD COLUMN IF NOT EXISTS "token_encryption_iv" text;
ALTER TABLE public.github_integrations ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.github_integrations ADD COLUMN IF NOT EXISTS "user_id" uuid;
ALTER TABLE public.github_integrations ADD COLUMN IF NOT EXISTS "access_token" text;
CREATE TABLE IF NOT EXISTS public.governance_proposals (
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "description" text NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "support_votes" integer DEFAULT 0 NOT NULL,
  "title" text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  "vote_count" integer DEFAULT 0 NOT NULL,
  "voting_ends_at" timestamp with time zone DEFAULT (now() + '72:00:00'::interval) NOT NULL,
  CONSTRAINT governance_proposals_pkey PRIMARY KEY (id)
);
ALTER TABLE public.governance_proposals ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.governance_proposals ADD COLUMN IF NOT EXISTS "description" text;
ALTER TABLE public.governance_proposals ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.governance_proposals ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.governance_proposals ADD COLUMN IF NOT EXISTS "support_votes" integer DEFAULT 0;
ALTER TABLE public.governance_proposals ADD COLUMN IF NOT EXISTS "title" text;
ALTER TABLE public.governance_proposals ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.governance_proposals ADD COLUMN IF NOT EXISTS "user_id" uuid;
ALTER TABLE public.governance_proposals ADD COLUMN IF NOT EXISTS "vote_count" integer DEFAULT 0;
ALTER TABLE public.governance_proposals ADD COLUMN IF NOT EXISTS "voting_ends_at" timestamp with time zone DEFAULT (now() + '72:00:00'::interval);
CREATE TABLE IF NOT EXISTS public.guardian_flash_alerts (
  "acted_at" timestamp with time zone,
  "acted_by" uuid,
  "action_taken" text,
  "alert_type" text NOT NULL,
  "asset_symbol" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "description" text,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "market_price" numeric,
  "severity" text DEFAULT 'medium'::text NOT NULL,
  "status" text DEFAULT 'active'::text NOT NULL,
  "title" text NOT NULL,
  "trigger_price" numeric,
  CONSTRAINT guardian_flash_alerts_pkey PRIMARY KEY (id)
);
ALTER TABLE public.guardian_flash_alerts ADD COLUMN IF NOT EXISTS "acted_at" timestamp with time zone;
ALTER TABLE public.guardian_flash_alerts ADD COLUMN IF NOT EXISTS "acted_by" uuid;
ALTER TABLE public.guardian_flash_alerts ADD COLUMN IF NOT EXISTS "action_taken" text;
ALTER TABLE public.guardian_flash_alerts ADD COLUMN IF NOT EXISTS "alert_type" text;
ALTER TABLE public.guardian_flash_alerts ADD COLUMN IF NOT EXISTS "asset_symbol" text;
ALTER TABLE public.guardian_flash_alerts ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.guardian_flash_alerts ADD COLUMN IF NOT EXISTS "description" text;
ALTER TABLE public.guardian_flash_alerts ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.guardian_flash_alerts ADD COLUMN IF NOT EXISTS "market_price" numeric;
ALTER TABLE public.guardian_flash_alerts ADD COLUMN IF NOT EXISTS "severity" text DEFAULT 'medium'::text;
ALTER TABLE public.guardian_flash_alerts ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'active'::text;
ALTER TABLE public.guardian_flash_alerts ADD COLUMN IF NOT EXISTS "title" text;
ALTER TABLE public.guardian_flash_alerts ADD COLUMN IF NOT EXISTS "trigger_price" numeric;
CREATE TABLE IF NOT EXISTS public.guardian_invitations (
  "accepted_at" timestamp with time zone,
  "accepted_by" uuid,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "expires_at" timestamp with time zone DEFAULT (now() + '30 days'::interval) NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "invited_by" uuid NOT NULL,
  "invited_email" text,
  "invited_str_domain" text,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT guardian_invitations_pkey PRIMARY KEY (id)
);
ALTER TABLE public.guardian_invitations ADD COLUMN IF NOT EXISTS "accepted_at" timestamp with time zone;
ALTER TABLE public.guardian_invitations ADD COLUMN IF NOT EXISTS "accepted_by" uuid;
ALTER TABLE public.guardian_invitations ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.guardian_invitations ADD COLUMN IF NOT EXISTS "expires_at" timestamp with time zone DEFAULT (now() + '30 days'::interval);
ALTER TABLE public.guardian_invitations ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.guardian_invitations ADD COLUMN IF NOT EXISTS "invited_by" uuid;
ALTER TABLE public.guardian_invitations ADD COLUMN IF NOT EXISTS "invited_email" text;
ALTER TABLE public.guardian_invitations ADD COLUMN IF NOT EXISTS "invited_str_domain" text;
ALTER TABLE public.guardian_invitations ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.guardian_invitations ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
CREATE TABLE IF NOT EXISTS public.guardian_wallets (
  "asset_name" text NOT NULL,
  "asset_symbol" text NOT NULL,
  "balance" numeric DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "deposit_address" text,
  "external_balance" numeric DEFAULT 0 NOT NULL,
  "icon_color" text DEFAULT '#F7931A'::text,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "is_active" boolean DEFAULT true NOT NULL,
  "network" text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "usd_value" numeric DEFAULT 0 NOT NULL,
  "user_external_address" text,
  "user_id" uuid NOT NULL,
  "wallet_address" text,
  CONSTRAINT guardian_wallets_pkey PRIMARY KEY (id)
);
ALTER TABLE public.guardian_wallets ADD COLUMN IF NOT EXISTS "asset_name" text;
ALTER TABLE public.guardian_wallets ADD COLUMN IF NOT EXISTS "asset_symbol" text;
ALTER TABLE public.guardian_wallets ADD COLUMN IF NOT EXISTS "balance" numeric DEFAULT 0;
ALTER TABLE public.guardian_wallets ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.guardian_wallets ADD COLUMN IF NOT EXISTS "deposit_address" text;
ALTER TABLE public.guardian_wallets ADD COLUMN IF NOT EXISTS "external_balance" numeric DEFAULT 0;
ALTER TABLE public.guardian_wallets ADD COLUMN IF NOT EXISTS "icon_color" text DEFAULT '#F7931A'::text;
ALTER TABLE public.guardian_wallets ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.guardian_wallets ADD COLUMN IF NOT EXISTS "is_active" boolean DEFAULT true;
ALTER TABLE public.guardian_wallets ADD COLUMN IF NOT EXISTS "network" text;
ALTER TABLE public.guardian_wallets ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.guardian_wallets ADD COLUMN IF NOT EXISTS "usd_value" numeric DEFAULT 0;
ALTER TABLE public.guardian_wallets ADD COLUMN IF NOT EXISTS "user_external_address" text;
ALTER TABLE public.guardian_wallets ADD COLUMN IF NOT EXISTS "user_id" uuid;
ALTER TABLE public.guardian_wallets ADD COLUMN IF NOT EXISTS "wallet_address" text;
CREATE TABLE IF NOT EXISTS public.iban_accounts (
  "account_category" text DEFAULT 'personal'::text,
  "account_holder" text NOT NULL,
  "account_type" text NOT NULL,
  "balance" numeric(18,8) DEFAULT 0,
  "bic" text NOT NULL,
  "country_code" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now(),
  "currency" text NOT NULL,
  "encrypted_bic" text,
  "encrypted_iban" text,
  "encryption_version" integer DEFAULT 0,
  "iban" text NOT NULL,
  "iban_encryption_iv" text,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "is_data_encrypted" boolean DEFAULT true,
  "legacy_iban" text,
  "merchant_account" boolean DEFAULT false,
  "pos_enabled" boolean DEFAULT false,
  "status" text DEFAULT 'active'::text,
  "updated_at" timestamp with time zone DEFAULT now(),
  "user_id" uuid NOT NULL,
  CONSTRAINT iban_accounts_pkey PRIMARY KEY (id)
);
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "account_category" text DEFAULT 'personal'::text;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "account_holder" text;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "account_type" text;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "balance" numeric(18,8) DEFAULT 0;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "bic" text;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "country_code" text;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "currency" text;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "encrypted_bic" text;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "encrypted_iban" text;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "encryption_version" integer DEFAULT 0;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "iban" text;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "iban_encryption_iv" text;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "is_data_encrypted" boolean DEFAULT true;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "legacy_iban" text;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "merchant_account" boolean DEFAULT false;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "pos_enabled" boolean DEFAULT false;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'active'::text;
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.iban_accounts ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.ipo_listing_requests (
  "address" text,
  "admin_message" text,
  "admin_notes" text,
  "bank_name" text NOT NULL,
  "bank_swift" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "email" text NOT NULL,
  "full_name" text NOT NULL,
  "iban" text NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "number_of_shares" integer NOT NULL,
  "phone" text,
  "price_per_share" numeric DEFAULT 91.3 NOT NULL,
  "processed_at" timestamp with time zone,
  "processed_by" text,
  "receiving_currency" text NOT NULL,
  "share_type" text NOT NULL,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "total_usd_value" numeric NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT ipo_listing_requests_pkey PRIMARY KEY (id)
);
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "address" text;
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "admin_message" text;
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "admin_notes" text;
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "bank_name" text;
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "bank_swift" text;
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "email" text;
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "full_name" text;
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "iban" text;
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "number_of_shares" integer;
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "phone" text;
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "price_per_share" numeric DEFAULT 91.3;
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "processed_at" timestamp with time zone;
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "processed_by" text;
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "receiving_currency" text;
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "share_type" text;
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "total_usd_value" numeric;
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.ipo_listing_requests ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.liquidity_pools (
  "apy_rate" numeric DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "description" text,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "is_active" boolean DEFAULT true NOT NULL,
  "pool_name" text NOT NULL,
  "pool_symbol" text NOT NULL,
  "pool_type" text NOT NULL,
  "total_liquidity" numeric DEFAULT 0 NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "base_token" text /* legacy: referenced by migration history */,
  "quote_token" text /* legacy: referenced by migration history */,
  "total_liquidity_usd" numeric NOT NULL DEFAULT 0 /* legacy: referenced by migration history */,
  "apy" numeric /* legacy: referenced by migration history */,
  "fee_percentage" numeric /* legacy: referenced by migration history */,
  CONSTRAINT liquidity_pools_pkey PRIMARY KEY (id)
);
ALTER TABLE public.liquidity_pools ADD COLUMN IF NOT EXISTS "apy_rate" numeric DEFAULT 0;
ALTER TABLE public.liquidity_pools ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.liquidity_pools ADD COLUMN IF NOT EXISTS "description" text;
ALTER TABLE public.liquidity_pools ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.liquidity_pools ADD COLUMN IF NOT EXISTS "is_active" boolean DEFAULT true;
ALTER TABLE public.liquidity_pools ADD COLUMN IF NOT EXISTS "pool_name" text;
ALTER TABLE public.liquidity_pools ADD COLUMN IF NOT EXISTS "pool_symbol" text;
ALTER TABLE public.liquidity_pools ADD COLUMN IF NOT EXISTS "pool_type" text;
ALTER TABLE public.liquidity_pools ADD COLUMN IF NOT EXISTS "total_liquidity" numeric DEFAULT 0;
ALTER TABLE public.liquidity_pools ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.liquidity_pools ADD COLUMN IF NOT EXISTS "base_token" text;
ALTER TABLE public.liquidity_pools ADD COLUMN IF NOT EXISTS "quote_token" text;
ALTER TABLE public.liquidity_pools ADD COLUMN IF NOT EXISTS "total_liquidity_usd" numeric NOT NULL DEFAULT 0;
ALTER TABLE public.liquidity_pools ADD COLUMN IF NOT EXISTS "apy" numeric;
ALTER TABLE public.liquidity_pools ADD COLUMN IF NOT EXISTS "fee_percentage" numeric;
CREATE TABLE IF NOT EXISTS public.liquidity_transactions (
  "amount" numeric NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "pool_id" uuid NOT NULL,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "transaction_hash" text,
  "transaction_type" text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT liquidity_transactions_pkey PRIMARY KEY (id)
);
ALTER TABLE public.liquidity_transactions ADD COLUMN IF NOT EXISTS "amount" numeric;
ALTER TABLE public.liquidity_transactions ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.liquidity_transactions ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.liquidity_transactions ADD COLUMN IF NOT EXISTS "pool_id" uuid;
ALTER TABLE public.liquidity_transactions ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.liquidity_transactions ADD COLUMN IF NOT EXISTS "transaction_hash" text;
ALTER TABLE public.liquidity_transactions ADD COLUMN IF NOT EXISTS "transaction_type" text;
ALTER TABLE public.liquidity_transactions ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.liquidity_transactions ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.member_support_tickets (
  "admin_notes" text,
  "category" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "error_details" text NOT NULL,
  "full_name" text,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "resolution_time_hours" integer DEFAULT 72,
  "resolved_at" timestamp with time zone,
  "resolved_by" uuid,
  "severity" text DEFAULT 'medium'::text NOT NULL,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "str_domain" text,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_email" text NOT NULL,
  "user_id" uuid NOT NULL,
  "user_phone" text,
  CONSTRAINT member_support_tickets_pkey PRIMARY KEY (id)
);
ALTER TABLE public.member_support_tickets ADD COLUMN IF NOT EXISTS "admin_notes" text;
ALTER TABLE public.member_support_tickets ADD COLUMN IF NOT EXISTS "category" text;
ALTER TABLE public.member_support_tickets ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.member_support_tickets ADD COLUMN IF NOT EXISTS "error_details" text;
ALTER TABLE public.member_support_tickets ADD COLUMN IF NOT EXISTS "full_name" text;
ALTER TABLE public.member_support_tickets ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.member_support_tickets ADD COLUMN IF NOT EXISTS "resolution_time_hours" integer DEFAULT 72;
ALTER TABLE public.member_support_tickets ADD COLUMN IF NOT EXISTS "resolved_at" timestamp with time zone;
ALTER TABLE public.member_support_tickets ADD COLUMN IF NOT EXISTS "resolved_by" uuid;
ALTER TABLE public.member_support_tickets ADD COLUMN IF NOT EXISTS "severity" text DEFAULT 'medium'::text;
ALTER TABLE public.member_support_tickets ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.member_support_tickets ADD COLUMN IF NOT EXISTS "str_domain" text;
ALTER TABLE public.member_support_tickets ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.member_support_tickets ADD COLUMN IF NOT EXISTS "user_email" text;
ALTER TABLE public.member_support_tickets ADD COLUMN IF NOT EXISTS "user_id" uuid;
ALTER TABLE public.member_support_tickets ADD COLUMN IF NOT EXISTS "user_phone" text;
CREATE TABLE IF NOT EXISTS public.merchant_business_ibans (
  "account_holder" text NOT NULL,
  "balance" numeric DEFAULT 0 NOT NULL,
  "bic" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "currency" text NOT NULL,
  "iban" text NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "is_encrypted" boolean DEFAULT false,
  "merchant_id" uuid NOT NULL,
  "status" text DEFAULT 'active'::text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT merchant_business_ibans_pkey PRIMARY KEY (id)
);
ALTER TABLE public.merchant_business_ibans ADD COLUMN IF NOT EXISTS "account_holder" text;
ALTER TABLE public.merchant_business_ibans ADD COLUMN IF NOT EXISTS "balance" numeric DEFAULT 0;
ALTER TABLE public.merchant_business_ibans ADD COLUMN IF NOT EXISTS "bic" text;
ALTER TABLE public.merchant_business_ibans ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.merchant_business_ibans ADD COLUMN IF NOT EXISTS "currency" text;
ALTER TABLE public.merchant_business_ibans ADD COLUMN IF NOT EXISTS "iban" text;
ALTER TABLE public.merchant_business_ibans ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.merchant_business_ibans ADD COLUMN IF NOT EXISTS "is_encrypted" boolean DEFAULT false;
ALTER TABLE public.merchant_business_ibans ADD COLUMN IF NOT EXISTS "merchant_id" uuid;
ALTER TABLE public.merchant_business_ibans ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'active'::text;
ALTER TABLE public.merchant_business_ibans ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.merchant_business_ibans ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.merchant_products (
  "category" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "crypto_currency" text,
  "crypto_price" numeric,
  "description" text,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "image_url" text,
  "is_active" boolean DEFAULT true,
  "is_digital" boolean DEFAULT false,
  "merchant_id" uuid NOT NULL,
  "metadata" jsonb DEFAULT '{}'::jsonb,
  "price" numeric NOT NULL,
  "price_currency" text DEFAULT 'EUR'::text NOT NULL,
  "product_name" text NOT NULL,
  "stock_quantity" integer,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT merchant_products_pkey PRIMARY KEY (id)
);
ALTER TABLE public.merchant_products ADD COLUMN IF NOT EXISTS "category" text;
ALTER TABLE public.merchant_products ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.merchant_products ADD COLUMN IF NOT EXISTS "crypto_currency" text;
ALTER TABLE public.merchant_products ADD COLUMN IF NOT EXISTS "crypto_price" numeric;
ALTER TABLE public.merchant_products ADD COLUMN IF NOT EXISTS "description" text;
ALTER TABLE public.merchant_products ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.merchant_products ADD COLUMN IF NOT EXISTS "image_url" text;
ALTER TABLE public.merchant_products ADD COLUMN IF NOT EXISTS "is_active" boolean DEFAULT true;
ALTER TABLE public.merchant_products ADD COLUMN IF NOT EXISTS "is_digital" boolean DEFAULT false;
ALTER TABLE public.merchant_products ADD COLUMN IF NOT EXISTS "merchant_id" uuid;
ALTER TABLE public.merchant_products ADD COLUMN IF NOT EXISTS "metadata" jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.merchant_products ADD COLUMN IF NOT EXISTS "price" numeric;
ALTER TABLE public.merchant_products ADD COLUMN IF NOT EXISTS "price_currency" text DEFAULT 'EUR'::text;
ALTER TABLE public.merchant_products ADD COLUMN IF NOT EXISTS "product_name" text;
ALTER TABLE public.merchant_products ADD COLUMN IF NOT EXISTS "stock_quantity" integer;
ALTER TABLE public.merchant_products ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.merchant_products ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.pending_profile_changes (
  "admin_notes" text,
  "change_reason" text,
  "confirmation_token" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "ip_address" inet,
  "requested_changes" jsonb NOT NULL,
  "reviewed_at" timestamp with time zone,
  "reviewed_by" uuid,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "token_expires_at" timestamp with time zone,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_agent" text,
  "user_id" uuid NOT NULL,
  CONSTRAINT pending_profile_changes_pkey PRIMARY KEY (id)
);
ALTER TABLE public.pending_profile_changes ADD COLUMN IF NOT EXISTS "admin_notes" text;
ALTER TABLE public.pending_profile_changes ADD COLUMN IF NOT EXISTS "change_reason" text;
ALTER TABLE public.pending_profile_changes ADD COLUMN IF NOT EXISTS "confirmation_token" text;
ALTER TABLE public.pending_profile_changes ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.pending_profile_changes ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.pending_profile_changes ADD COLUMN IF NOT EXISTS "ip_address" inet;
ALTER TABLE public.pending_profile_changes ADD COLUMN IF NOT EXISTS "requested_changes" jsonb;
ALTER TABLE public.pending_profile_changes ADD COLUMN IF NOT EXISTS "reviewed_at" timestamp with time zone;
ALTER TABLE public.pending_profile_changes ADD COLUMN IF NOT EXISTS "reviewed_by" uuid;
ALTER TABLE public.pending_profile_changes ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.pending_profile_changes ADD COLUMN IF NOT EXISTS "token_expires_at" timestamp with time zone;
ALTER TABLE public.pending_profile_changes ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.pending_profile_changes ADD COLUMN IF NOT EXISTS "user_agent" text;
ALTER TABLE public.pending_profile_changes ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.praeco_peers (
  "address" text NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "is_online" boolean DEFAULT true,
  "last_seen" timestamp with time zone DEFAULT now(),
  "metadata" jsonb DEFAULT '{}'::jsonb,
  "node_id" text NOT NULL,
  "node_type" text DEFAULT 'light'::text NOT NULL,
  "port" integer DEFAULT 33100,
  "user_id" text NOT NULL,
  CONSTRAINT praeco_peers_pkey PRIMARY KEY (id)
);
ALTER TABLE public.praeco_peers ADD COLUMN IF NOT EXISTS "address" text;
ALTER TABLE public.praeco_peers ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.praeco_peers ADD COLUMN IF NOT EXISTS "is_online" boolean DEFAULT true;
ALTER TABLE public.praeco_peers ADD COLUMN IF NOT EXISTS "last_seen" timestamp with time zone DEFAULT now();
ALTER TABLE public.praeco_peers ADD COLUMN IF NOT EXISTS "metadata" jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.praeco_peers ADD COLUMN IF NOT EXISTS "node_id" text;
ALTER TABLE public.praeco_peers ADD COLUMN IF NOT EXISTS "node_type" text DEFAULT 'light'::text;
ALTER TABLE public.praeco_peers ADD COLUMN IF NOT EXISTS "port" integer DEFAULT 33100;
ALTER TABLE public.praeco_peers ADD COLUMN IF NOT EXISTS "user_id" text;
CREATE TABLE IF NOT EXISTS public.prepaid_cards (
  "balance" numeric DEFAULT 0 NOT NULL,
  "bin" text,
  "card_last4" text NOT NULL,
  "card_status" text DEFAULT 'active'::text,
  "card_type" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "currency" text NOT NULL,
  "domain_part" text,
  "expiry_date" date,
  "full_identifier" text,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "issuer" text DEFAULT 'ARESfin'::text,
  "masked_card" text NOT NULL,
  "metadata" jsonb,
  "network" text DEFAULT 'visa'::text NOT NULL,
  "pan_hash" text,
  "physical_card" boolean DEFAULT false,
  "shipping_status" text,
  "status" text DEFAULT 'active'::text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  "wallet_suffix" text,
  CONSTRAINT prepaid_cards_pkey PRIMARY KEY (id)
);
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "balance" numeric DEFAULT 0;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "bin" text;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "card_last4" text;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "card_status" text DEFAULT 'active'::text;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "card_type" text;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "currency" text;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "domain_part" text;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "expiry_date" date;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "full_identifier" text;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "issuer" text DEFAULT 'ARESfin'::text;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "masked_card" text;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "metadata" jsonb;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "network" text DEFAULT 'visa'::text;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "pan_hash" text;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "physical_card" boolean DEFAULT false;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "shipping_status" text;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'active'::text;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "user_id" uuid;
ALTER TABLE public.prepaid_cards ADD COLUMN IF NOT EXISTS "wallet_suffix" text;
CREATE TABLE IF NOT EXISTS public.private_seed_str_applications (
  "acknowledgment_accepted" boolean DEFAULT false NOT NULL,
  "admin_notes" text,
  "application_date" timestamp with time zone DEFAULT now(),
  "browser" text,
  "cancelled_at" timestamp with time zone,
  "cancelled_by" uuid,
  "city" text,
  "country" text,
  "created_at" timestamp with time zone DEFAULT now(),
  "credited_amount" numeric DEFAULT 0,
  "credited_at" timestamp with time zone,
  "device_type" text,
  "email" text NOT NULL,
  "expected_return_rate" numeric DEFAULT 0,
  "full_name" text NOT NULL,
  "gdpr_accepted" boolean DEFAULT false,
  "gdpr_accepted_at" timestamp with time zone,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "investment_amount" numeric DEFAULT 0,
  "investment_tier" text,
  "ip_address" inet DEFAULT '0.0.0.0'::inet,
  "location_city" text,
  "location_country" text,
  "lock_period_months" integer DEFAULT 12,
  "metadata" jsonb DEFAULT '{}'::jsonb,
  "nda_accepted" boolean DEFAULT false,
  "nda_accepted_at" timestamp with time zone,
  "payment_amount" numeric,
  "payment_crypto" text,
  "payment_deadline" timestamp with time zone,
  "payment_hash" text,
  "payment_status" text DEFAULT 'awaiting_payment'::text,
  "payment_submitted_at" timestamp with time zone,
  "phone" text,
  "postal_code" text,
  "presented_by" text,
  "processed_at" timestamp with time zone,
  "processed_by" uuid,
  "purpose_of_report" text,
  "risk_disclosure_accepted" boolean DEFAULT false,
  "risk_disclosure_accepted_at" timestamp with time zone,
  "signature_date" timestamp with time zone,
  "signature_first_name" text,
  "signature_last_name" text,
  "state_province" text,
  "status" text DEFAULT 'pending'::text,
  "str_backing_amount" numeric DEFAULT 0,
  "str_shares_credited" numeric DEFAULT 0,
  "street_address" text,
  "suspended_at" timestamp with time zone,
  "suspended_by" uuid,
  "suspension_reason" text,
  "terms_accepted" boolean DEFAULT false,
  "terms_accepted_at" timestamp with time zone,
  "updated_at" timestamp with time zone DEFAULT now(),
  "user_agent" text,
  "user_id" uuid NOT NULL,
  CONSTRAINT private_seed_str_applications_pkey PRIMARY KEY (id)
);
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "acknowledgment_accepted" boolean DEFAULT false;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "admin_notes" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "application_date" timestamp with time zone DEFAULT now();
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "browser" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "cancelled_at" timestamp with time zone;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "cancelled_by" uuid;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "city" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "country" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "credited_amount" numeric DEFAULT 0;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "credited_at" timestamp with time zone;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "device_type" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "email" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "expected_return_rate" numeric DEFAULT 0;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "full_name" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "gdpr_accepted" boolean DEFAULT false;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "gdpr_accepted_at" timestamp with time zone;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "investment_amount" numeric DEFAULT 0;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "investment_tier" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "ip_address" inet DEFAULT '0.0.0.0'::inet;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "location_city" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "location_country" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "lock_period_months" integer DEFAULT 12;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "metadata" jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "nda_accepted" boolean DEFAULT false;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "nda_accepted_at" timestamp with time zone;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "payment_amount" numeric;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "payment_crypto" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "payment_deadline" timestamp with time zone;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "payment_hash" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "payment_status" text DEFAULT 'awaiting_payment'::text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "payment_submitted_at" timestamp with time zone;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "phone" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "postal_code" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "presented_by" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "processed_at" timestamp with time zone;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "processed_by" uuid;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "purpose_of_report" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "risk_disclosure_accepted" boolean DEFAULT false;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "risk_disclosure_accepted_at" timestamp with time zone;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "signature_date" timestamp with time zone;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "signature_first_name" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "signature_last_name" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "state_province" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "str_backing_amount" numeric DEFAULT 0;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "str_shares_credited" numeric DEFAULT 0;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "street_address" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "suspended_at" timestamp with time zone;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "suspended_by" uuid;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "suspension_reason" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "terms_accepted" boolean DEFAULT false;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "terms_accepted_at" timestamp with time zone;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "user_agent" text;
ALTER TABLE public.private_seed_str_applications ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.private_seed_str_audit_log (
  "action_details" jsonb DEFAULT '{}'::jsonb,
  "action_type" text NOT NULL,
  "application_id" uuid,
  "created_at" timestamp with time zone DEFAULT now(),
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "performed_by" uuid NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT private_seed_str_audit_log_pkey PRIMARY KEY (id)
);
ALTER TABLE public.private_seed_str_audit_log ADD COLUMN IF NOT EXISTS "action_details" jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.private_seed_str_audit_log ADD COLUMN IF NOT EXISTS "action_type" text;
ALTER TABLE public.private_seed_str_audit_log ADD COLUMN IF NOT EXISTS "application_id" uuid;
ALTER TABLE public.private_seed_str_audit_log ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.private_seed_str_audit_log ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.private_seed_str_audit_log ADD COLUMN IF NOT EXISTS "performed_by" uuid;
ALTER TABLE public.private_seed_str_audit_log ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.profile_changes (
  "change_reason" text,
  "changed_by" uuid NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "field_name" text NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "ip_address" inet,
  "new_value" text,
  "old_value" text,
  "user_agent" text,
  "user_id" uuid NOT NULL,
  CONSTRAINT profile_changes_pkey PRIMARY KEY (id)
);
ALTER TABLE public.profile_changes ADD COLUMN IF NOT EXISTS "change_reason" text;
ALTER TABLE public.profile_changes ADD COLUMN IF NOT EXISTS "changed_by" uuid;
ALTER TABLE public.profile_changes ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.profile_changes ADD COLUMN IF NOT EXISTS "field_name" text;
ALTER TABLE public.profile_changes ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.profile_changes ADD COLUMN IF NOT EXISTS "ip_address" inet;
ALTER TABLE public.profile_changes ADD COLUMN IF NOT EXISTS "new_value" text;
ALTER TABLE public.profile_changes ADD COLUMN IF NOT EXISTS "old_value" text;
ALTER TABLE public.profile_changes ADD COLUMN IF NOT EXISTS "user_agent" text;
ALTER TABLE public.profile_changes ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.profiles (
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "email" text NOT NULL,
  "full_name" text,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "role" text DEFAULT 'user'::text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT profiles_pkey PRIMARY KEY (id)
);
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS "email" text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS "full_name" text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS "role" text DEFAULT 'user'::text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.safe_admins (
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "full_name" text,
  "granted_by" uuid,
  "user_id" uuid NOT NULL,
  CONSTRAINT safe_admins_pkey PRIMARY KEY (user_id)
);
ALTER TABLE public.safe_admins ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.safe_admins ADD COLUMN IF NOT EXISTS "full_name" text;
ALTER TABLE public.safe_admins ADD COLUMN IF NOT EXISTS "granted_by" uuid;
ALTER TABLE public.safe_admins ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.safe_purchases (
  "address" text NOT NULL,
  "bonus_pct" numeric(5,2) DEFAULT 0 NOT NULL,
  "bonus_shares" integer DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "credited_at" timestamp with time zone,
  "credited_by" uuid,
  "credited_shares" integer,
  "crypto" text NOT NULL,
  "email" text NOT NULL,
  "full_name" text NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "notes" text,
  "pep_declared" boolean DEFAULT false NOT NULL,
  "phone" text NOT NULL,
  "presenter_email" text,
  "presenter_full_name" text,
  "presenter_phone" text,
  "presenter_ref" text,
  "price_per_share_usd" numeric(12,2) DEFAULT 20 NOT NULL,
  "shares" integer NOT NULL,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "total_shares" integer NOT NULL,
  "total_usd" numeric(14,2) NOT NULL,
  "tx_hash" text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid,
  CONSTRAINT safe_purchases_pkey PRIMARY KEY (id)
);
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "address" text;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "bonus_pct" numeric(5,2) DEFAULT 0;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "bonus_shares" integer DEFAULT 0;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "credited_at" timestamp with time zone;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "credited_by" uuid;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "credited_shares" integer;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "crypto" text;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "email" text;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "full_name" text;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "notes" text;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "pep_declared" boolean DEFAULT false;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "phone" text;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "presenter_email" text;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "presenter_full_name" text;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "presenter_phone" text;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "presenter_ref" text;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "price_per_share_usd" numeric(12,2) DEFAULT 20;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "shares" integer;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "total_shares" integer;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "total_usd" numeric(14,2);
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "tx_hash" text;
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.safe_purchases ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.security_audit_log (
  "action" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now(),
  "details" jsonb,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "ip_address" inet,
  "resource_id" text,
  "resource_type" text NOT NULL,
  "user_agent" text,
  "user_id" uuid,
  CONSTRAINT security_audit_log_pkey PRIMARY KEY (id)
);
ALTER TABLE public.security_audit_log ADD COLUMN IF NOT EXISTS "action" text;
ALTER TABLE public.security_audit_log ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.security_audit_log ADD COLUMN IF NOT EXISTS "details" jsonb;
ALTER TABLE public.security_audit_log ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.security_audit_log ADD COLUMN IF NOT EXISTS "ip_address" inet;
ALTER TABLE public.security_audit_log ADD COLUMN IF NOT EXISTS "resource_id" text;
ALTER TABLE public.security_audit_log ADD COLUMN IF NOT EXISTS "resource_type" text;
ALTER TABLE public.security_audit_log ADD COLUMN IF NOT EXISTS "user_agent" text;
ALTER TABLE public.security_audit_log ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.seed_str_affiliates (
  "affiliate_code" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "email" text NOT NULL,
  "full_name" text NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "status" text DEFAULT 'active'::text,
  "str_domain" text NOT NULL,
  "total_conversions" integer DEFAULT 0,
  "total_investment_referred" numeric DEFAULT 0,
  "total_referrals" integer DEFAULT 0,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "usdc_address" text,
  "usdc_network" text,
  "usdt_address" text,
  "usdt_network" text,
  "user_id" uuid NOT NULL,
  CONSTRAINT seed_str_affiliates_pkey PRIMARY KEY (id)
);
ALTER TABLE public.seed_str_affiliates ADD COLUMN IF NOT EXISTS "affiliate_code" text;
ALTER TABLE public.seed_str_affiliates ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.seed_str_affiliates ADD COLUMN IF NOT EXISTS "email" text;
ALTER TABLE public.seed_str_affiliates ADD COLUMN IF NOT EXISTS "full_name" text;
ALTER TABLE public.seed_str_affiliates ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.seed_str_affiliates ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'active'::text;
ALTER TABLE public.seed_str_affiliates ADD COLUMN IF NOT EXISTS "str_domain" text;
ALTER TABLE public.seed_str_affiliates ADD COLUMN IF NOT EXISTS "total_conversions" integer DEFAULT 0;
ALTER TABLE public.seed_str_affiliates ADD COLUMN IF NOT EXISTS "total_investment_referred" numeric DEFAULT 0;
ALTER TABLE public.seed_str_affiliates ADD COLUMN IF NOT EXISTS "total_referrals" integer DEFAULT 0;
ALTER TABLE public.seed_str_affiliates ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.seed_str_affiliates ADD COLUMN IF NOT EXISTS "usdc_address" text;
ALTER TABLE public.seed_str_affiliates ADD COLUMN IF NOT EXISTS "usdc_network" text;
ALTER TABLE public.seed_str_affiliates ADD COLUMN IF NOT EXISTS "usdt_address" text;
ALTER TABLE public.seed_str_affiliates ADD COLUMN IF NOT EXISTS "usdt_network" text;
ALTER TABLE public.seed_str_affiliates ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.seed_str_applications (
  "admin_notes" text,
  "affiliate_email" text,
  "affiliate_id" uuid,
  "affiliate_name" text,
  "application_date" timestamp with time zone DEFAULT now() NOT NULL,
  "cancelled_at" timestamp with time zone,
  "cancelled_by" uuid,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "credited_amount" numeric DEFAULT 0,
  "credited_at" timestamp with time zone,
  "email" text NOT NULL,
  "expected_return_rate" numeric DEFAULT 0 NOT NULL,
  "full_name" text NOT NULL,
  "gdpr_accepted" boolean DEFAULT false NOT NULL,
  "gdpr_accepted_at" timestamp with time zone,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "investment_amount" numeric DEFAULT 0 NOT NULL,
  "investment_currency" text DEFAULT 'STR'::text NOT NULL,
  "investment_tier" text DEFAULT 'standard'::text NOT NULL,
  "ip_address" inet,
  "lock_period_months" integer DEFAULT 12 NOT NULL,
  "metadata" jsonb DEFAULT '{}'::jsonb,
  "nda_accepted" boolean DEFAULT false NOT NULL,
  "nda_accepted_at" timestamp with time zone,
  "payment_amount" numeric,
  "payment_crypto" text,
  "payment_deadline" timestamp with time zone,
  "payment_hash" text,
  "payment_status" text DEFAULT 'awaiting_payment'::text,
  "payment_submitted_at" timestamp with time zone,
  "payment_verified_at" timestamp with time zone,
  "payment_verified_by" uuid,
  "processed_at" timestamp with time zone,
  "processed_by" uuid,
  "risk_disclosure_accepted" boolean DEFAULT false NOT NULL,
  "risk_disclosure_accepted_at" timestamp with time zone,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "str_backing_amount" numeric DEFAULT 0 NOT NULL,
  "str_shares_credited" numeric DEFAULT 0,
  "suspended_at" timestamp with time zone,
  "suspended_by" uuid,
  "suspension_reason" text,
  "terms_accepted" boolean DEFAULT false NOT NULL,
  "terms_accepted_at" timestamp with time zone,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_agent" text,
  "user_id" uuid NOT NULL,
  CONSTRAINT seed_str_applications_pkey PRIMARY KEY (id)
);
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "admin_notes" text;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "affiliate_email" text;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "affiliate_id" uuid;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "affiliate_name" text;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "application_date" timestamp with time zone DEFAULT now();
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "cancelled_at" timestamp with time zone;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "cancelled_by" uuid;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "credited_amount" numeric DEFAULT 0;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "credited_at" timestamp with time zone;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "email" text;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "expected_return_rate" numeric DEFAULT 0;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "full_name" text;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "gdpr_accepted" boolean DEFAULT false;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "gdpr_accepted_at" timestamp with time zone;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "investment_amount" numeric DEFAULT 0;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "investment_currency" text DEFAULT 'STR'::text;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "investment_tier" text DEFAULT 'standard'::text;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "ip_address" inet;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "lock_period_months" integer DEFAULT 12;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "metadata" jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "nda_accepted" boolean DEFAULT false;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "nda_accepted_at" timestamp with time zone;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "payment_amount" numeric;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "payment_crypto" text;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "payment_deadline" timestamp with time zone;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "payment_hash" text;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "payment_status" text DEFAULT 'awaiting_payment'::text;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "payment_submitted_at" timestamp with time zone;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "payment_verified_at" timestamp with time zone;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "payment_verified_by" uuid;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "processed_at" timestamp with time zone;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "processed_by" uuid;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "risk_disclosure_accepted" boolean DEFAULT false;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "risk_disclosure_accepted_at" timestamp with time zone;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "str_backing_amount" numeric DEFAULT 0;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "str_shares_credited" numeric DEFAULT 0;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "suspended_at" timestamp with time zone;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "suspended_by" uuid;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "suspension_reason" text;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "terms_accepted" boolean DEFAULT false;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "terms_accepted_at" timestamp with time zone;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "user_agent" text;
ALTER TABLE public.seed_str_applications ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.seed_str_audit_log (
  "action_details" jsonb,
  "action_type" text NOT NULL,
  "application_id" uuid,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "ip_address" inet,
  "performed_by" uuid NOT NULL,
  "user_agent" text,
  "user_id" uuid NOT NULL,
  CONSTRAINT seed_str_audit_log_pkey PRIMARY KEY (id)
);
ALTER TABLE public.seed_str_audit_log ADD COLUMN IF NOT EXISTS "action_details" jsonb;
ALTER TABLE public.seed_str_audit_log ADD COLUMN IF NOT EXISTS "action_type" text;
ALTER TABLE public.seed_str_audit_log ADD COLUMN IF NOT EXISTS "application_id" uuid;
ALTER TABLE public.seed_str_audit_log ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.seed_str_audit_log ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.seed_str_audit_log ADD COLUMN IF NOT EXISTS "ip_address" inet;
ALTER TABLE public.seed_str_audit_log ADD COLUMN IF NOT EXISTS "performed_by" uuid;
ALTER TABLE public.seed_str_audit_log ADD COLUMN IF NOT EXISTS "user_agent" text;
ALTER TABLE public.seed_str_audit_log ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.staking_data_cache (
  "cache_key" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now(),
  "data" jsonb NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now(),
  CONSTRAINT staking_data_cache_pkey PRIMARY KEY (id)
);
ALTER TABLE public.staking_data_cache ADD COLUMN IF NOT EXISTS "cache_key" text;
ALTER TABLE public.staking_data_cache ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.staking_data_cache ADD COLUMN IF NOT EXISTS "data" jsonb;
ALTER TABLE public.staking_data_cache ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.staking_data_cache ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
CREATE TABLE IF NOT EXISTS public.staking_requests (
  "admin_notes" text,
  "amount" numeric NOT NULL,
  "approved_by" uuid,
  "created_at" timestamp with time zone DEFAULT now(),
  "description" text,
  "domain_name" text,
  "duration_months" integer NOT NULL,
  "full_name" text,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "pool_type" text NOT NULL,
  "processed_at" timestamp with time zone,
  "request_type" text NOT NULL,
  "requested_at" timestamp with time zone DEFAULT now(),
  "status" text DEFAULT 'pending'::text NOT NULL,
  "str_domain_owned" text,
  "str_domain_username" text,
  "transaction_hash" text,
  "updated_at" timestamp with time zone DEFAULT now(),
  "user_id" uuid NOT NULL,
  CONSTRAINT staking_requests_pkey PRIMARY KEY (id)
);
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "admin_notes" text;
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "amount" numeric;
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "approved_by" uuid;
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "description" text;
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "domain_name" text;
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "duration_months" integer;
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "full_name" text;
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "pool_type" text;
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "processed_at" timestamp with time zone;
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "request_type" text;
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "requested_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "str_domain_owned" text;
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "str_domain_username" text;
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "transaction_hash" text;
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.staking_requests ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.staking_rewards_distribution (
  "calculated_apy" numeric(5,2) NOT NULL,
  "created_at" timestamp with time zone DEFAULT now(),
  "distribution_date" date DEFAULT CURRENT_DATE,
  "estimated_reward" numeric NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "network_efficiency" numeric(3,2) DEFAULT 1.0,
  "pool_id" uuid NOT NULL,
  "stake_amount" numeric NOT NULL,
  "status" text DEFAULT 'pending'::text,
  "user_id" uuid NOT NULL,
  CONSTRAINT staking_rewards_distribution_pkey PRIMARY KEY (id)
);
ALTER TABLE public.staking_rewards_distribution ADD COLUMN IF NOT EXISTS "calculated_apy" numeric(5,2);
ALTER TABLE public.staking_rewards_distribution ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.staking_rewards_distribution ADD COLUMN IF NOT EXISTS "distribution_date" date DEFAULT CURRENT_DATE;
ALTER TABLE public.staking_rewards_distribution ADD COLUMN IF NOT EXISTS "estimated_reward" numeric;
ALTER TABLE public.staking_rewards_distribution ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.staking_rewards_distribution ADD COLUMN IF NOT EXISTS "network_efficiency" numeric(3,2) DEFAULT 1.0;
ALTER TABLE public.staking_rewards_distribution ADD COLUMN IF NOT EXISTS "pool_id" uuid;
ALTER TABLE public.staking_rewards_distribution ADD COLUMN IF NOT EXISTS "stake_amount" numeric;
ALTER TABLE public.staking_rewards_distribution ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.staking_rewards_distribution ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.str_domains (
  "approved_at" timestamp with time zone,
  "approved_by" uuid,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "domain_name" text NOT NULL,
  "domain_type" text NOT NULL,
  "domains_count" integer DEFAULT 1,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "is_from_str_dome" boolean DEFAULT false,
  "is_main_domain" boolean DEFAULT false,
  "metadata" jsonb DEFAULT '{}'::jsonb,
  "minted_at" timestamp with time zone,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "str_dome_purchase_date" timestamp with time zone,
  "str_dome_transaction_id" text,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT str_domains_pkey PRIMARY KEY (id)
);
ALTER TABLE public.str_domains ADD COLUMN IF NOT EXISTS "approved_at" timestamp with time zone;
ALTER TABLE public.str_domains ADD COLUMN IF NOT EXISTS "approved_by" uuid;
ALTER TABLE public.str_domains ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.str_domains ADD COLUMN IF NOT EXISTS "domain_name" text;
ALTER TABLE public.str_domains ADD COLUMN IF NOT EXISTS "domain_type" text;
ALTER TABLE public.str_domains ADD COLUMN IF NOT EXISTS "domains_count" integer DEFAULT 1;
ALTER TABLE public.str_domains ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.str_domains ADD COLUMN IF NOT EXISTS "is_from_str_dome" boolean DEFAULT false;
ALTER TABLE public.str_domains ADD COLUMN IF NOT EXISTS "is_main_domain" boolean DEFAULT false;
ALTER TABLE public.str_domains ADD COLUMN IF NOT EXISTS "metadata" jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.str_domains ADD COLUMN IF NOT EXISTS "minted_at" timestamp with time zone;
ALTER TABLE public.str_domains ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.str_domains ADD COLUMN IF NOT EXISTS "str_dome_purchase_date" timestamp with time zone;
ALTER TABLE public.str_domains ADD COLUMN IF NOT EXISTS "str_dome_transaction_id" text;
ALTER TABLE public.str_domains ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.str_domains ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.str_dome_requests (
  "account_email" text NOT NULL,
  "admin_notes" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "deliver_to_wallet" boolean DEFAULT false NOT NULL,
  "delivery_email" text,
  "esim_country" text NOT NULL,
  "esim_file_path" text,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "notes" text,
  "package_name" text NOT NULL,
  "package_price_usd" numeric NOT NULL,
  "reviewed_at" timestamp with time zone,
  "reviewed_by" uuid,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "str_dome_username" text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT str_dome_requests_pkey PRIMARY KEY (id)
);
ALTER TABLE public.str_dome_requests ADD COLUMN IF NOT EXISTS "account_email" text;
ALTER TABLE public.str_dome_requests ADD COLUMN IF NOT EXISTS "admin_notes" text;
ALTER TABLE public.str_dome_requests ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.str_dome_requests ADD COLUMN IF NOT EXISTS "deliver_to_wallet" boolean DEFAULT false;
ALTER TABLE public.str_dome_requests ADD COLUMN IF NOT EXISTS "delivery_email" text;
ALTER TABLE public.str_dome_requests ADD COLUMN IF NOT EXISTS "esim_country" text;
ALTER TABLE public.str_dome_requests ADD COLUMN IF NOT EXISTS "esim_file_path" text;
ALTER TABLE public.str_dome_requests ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.str_dome_requests ADD COLUMN IF NOT EXISTS "notes" text;
ALTER TABLE public.str_dome_requests ADD COLUMN IF NOT EXISTS "package_name" text;
ALTER TABLE public.str_dome_requests ADD COLUMN IF NOT EXISTS "package_price_usd" numeric;
ALTER TABLE public.str_dome_requests ADD COLUMN IF NOT EXISTS "reviewed_at" timestamp with time zone;
ALTER TABLE public.str_dome_requests ADD COLUMN IF NOT EXISTS "reviewed_by" uuid;
ALTER TABLE public.str_dome_requests ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.str_dome_requests ADD COLUMN IF NOT EXISTS "str_dome_username" text;
ALTER TABLE public.str_dome_requests ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.str_dome_requests ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.user_liquidity_positions (
  "amount_deposited" numeric DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "pool_id" uuid NOT NULL,
  "rewards_earned" numeric DEFAULT 0 NOT NULL,
  "share_percentage" numeric DEFAULT 0 NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT user_liquidity_positions_pkey PRIMARY KEY (id)
);
ALTER TABLE public.user_liquidity_positions ADD COLUMN IF NOT EXISTS "amount_deposited" numeric DEFAULT 0;
ALTER TABLE public.user_liquidity_positions ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.user_liquidity_positions ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.user_liquidity_positions ADD COLUMN IF NOT EXISTS "pool_id" uuid;
ALTER TABLE public.user_liquidity_positions ADD COLUMN IF NOT EXISTS "rewards_earned" numeric DEFAULT 0;
ALTER TABLE public.user_liquidity_positions ADD COLUMN IF NOT EXISTS "share_percentage" numeric DEFAULT 0;
ALTER TABLE public.user_liquidity_positions ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.user_liquidity_positions ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.user_messages (
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "is_popup_shown" boolean DEFAULT false NOT NULL,
  "is_read" boolean DEFAULT false NOT NULL,
  "message" text NOT NULL,
  "message_type" text DEFAULT 'info'::text NOT NULL,
  "read_at" timestamp with time zone,
  "recipient_id" uuid NOT NULL,
  "sender_id" uuid NOT NULL,
  "subject" text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT user_messages_pkey PRIMARY KEY (id)
);
ALTER TABLE public.user_messages ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.user_messages ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.user_messages ADD COLUMN IF NOT EXISTS "is_popup_shown" boolean DEFAULT false;
ALTER TABLE public.user_messages ADD COLUMN IF NOT EXISTS "is_read" boolean DEFAULT false;
ALTER TABLE public.user_messages ADD COLUMN IF NOT EXISTS "message" text;
ALTER TABLE public.user_messages ADD COLUMN IF NOT EXISTS "message_type" text DEFAULT 'info'::text;
ALTER TABLE public.user_messages ADD COLUMN IF NOT EXISTS "read_at" timestamp with time zone;
ALTER TABLE public.user_messages ADD COLUMN IF NOT EXISTS "recipient_id" uuid;
ALTER TABLE public.user_messages ADD COLUMN IF NOT EXISTS "sender_id" uuid;
ALTER TABLE public.user_messages ADD COLUMN IF NOT EXISTS "subject" text;
ALTER TABLE public.user_messages ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
CREATE TABLE IF NOT EXISTS public.user_profiles (
  "account_status" text DEFAULT 'active'::text NOT NULL,
  "address" text NOT NULL,
  "airdrop_applications_count" integer DEFAULT 0,
  "backup_codes" text[],
  "bsc_wallet_address" text NOT NULL,
  "btc_wallet_address" text NOT NULL,
  "ccoin_offshore_account_usd" text DEFAULT 'not connected/pending'::text,
  "ccoin_visa_card" text DEFAULT 'not connected/pending'::text,
  "city" text NOT NULL,
  "closed_at" timestamp with time zone,
  "closure_reason" text,
  "country" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "crypto_experience_level" text,
  "device_fingerprints" jsonb DEFAULT '[]'::jsonb,
  "email_address" text NOT NULL,
  "encryption_version" integer DEFAULT 0,
  "expected_monthly_volume_eur" numeric,
  "full_name" text NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "investor_classification" text,
  "ip_address" inet,
  "is_pep" boolean DEFAULT false,
  "last_airdrop_application_date" timestamp with time zone,
  "mica_approved_at" timestamp with time zone,
  "mica_profile_source_id" uuid,
  "mica_terms_accepted" boolean DEFAULT false,
  "mica_terms_accepted_at" timestamp with time zone,
  "mica_terms_version" text,
  "postal_code" text NOT NULL,
  "profile_update_status" text DEFAULT 'not_submitted'::text NOT NULL,
  "recovery_words_encrypted" boolean DEFAULT true,
  "recovery_words_iv" text,
  "recovery_words_shown" boolean DEFAULT false,
  "referral_code" text DEFAULT SUBSTRING(md5(((random())::text || (gen_random_uuid())::text)) FROM 1 FOR 8),
  "referred_by" uuid,
  "region" text,
  "risk_acknowledged" boolean DEFAULT false,
  "sanctions_declaration" boolean DEFAULT false,
  "source_of_funds" text,
  "source_of_wealth" text,
  "status" public.account_status DEFAULT 'pending'::account_status,
  "str_domain_owned" text NOT NULL,
  "str_domain_username" text NOT NULL,
  "str_wallet_address" text,
  "suspended_at" timestamp with time zone,
  "suspension_reason" text,
  "tax_identification_number" text,
  "tax_residency_country" text,
  "two_factor_enabled" boolean DEFAULT false,
  "two_factor_secret" text,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  "user_status" public.user_status DEFAULT 'standard'::user_status,
  "wallet_created_at" timestamp with time zone,
  "wallet_pin_hash" text,
  "wallet_recovery_words" text[],
  "wallet_setup_completed" boolean DEFAULT false,
  CONSTRAINT user_profiles_pkey PRIMARY KEY (id)
);
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "account_status" text DEFAULT 'active'::text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "address" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "airdrop_applications_count" integer DEFAULT 0;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "backup_codes" text[];
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "bsc_wallet_address" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "btc_wallet_address" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "ccoin_offshore_account_usd" text DEFAULT 'not connected/pending'::text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "ccoin_visa_card" text DEFAULT 'not connected/pending'::text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "city" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "closed_at" timestamp with time zone;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "closure_reason" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "country" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "crypto_experience_level" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "device_fingerprints" jsonb DEFAULT '[]'::jsonb;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "email_address" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "encryption_version" integer DEFAULT 0;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "expected_monthly_volume_eur" numeric;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "full_name" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "investor_classification" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "ip_address" inet;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "is_pep" boolean DEFAULT false;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "last_airdrop_application_date" timestamp with time zone;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "mica_approved_at" timestamp with time zone;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "mica_profile_source_id" uuid;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "mica_terms_accepted" boolean DEFAULT false;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "mica_terms_accepted_at" timestamp with time zone;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "mica_terms_version" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "postal_code" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "profile_update_status" text DEFAULT 'not_submitted'::text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "recovery_words_encrypted" boolean DEFAULT true;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "recovery_words_iv" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "recovery_words_shown" boolean DEFAULT false;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "referral_code" text DEFAULT SUBSTRING(md5(((random())::text || (gen_random_uuid())::text)) FROM 1 FOR 8);
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "referred_by" uuid;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "region" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "risk_acknowledged" boolean DEFAULT false;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "sanctions_declaration" boolean DEFAULT false;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "source_of_funds" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "source_of_wealth" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "status" public.account_status DEFAULT 'pending'::account_status;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "str_domain_owned" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "str_domain_username" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "str_wallet_address" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "suspended_at" timestamp with time zone;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "suspension_reason" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "tax_identification_number" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "tax_residency_country" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "two_factor_enabled" boolean DEFAULT false;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "two_factor_secret" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "user_id" uuid;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "user_status" public.user_status DEFAULT 'standard'::user_status;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "wallet_created_at" timestamp with time zone;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "wallet_pin_hash" text;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "wallet_recovery_words" text[];
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS "wallet_setup_completed" boolean DEFAULT false;
CREATE TABLE IF NOT EXISTS public.user_roles (
  "created_at" timestamp with time zone DEFAULT now(),
  "created_by" uuid,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "role" public.app_role NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT user_roles_pkey PRIMARY KEY (id)
);
ALTER TABLE public.user_roles ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.user_roles ADD COLUMN IF NOT EXISTS "created_by" uuid;
ALTER TABLE public.user_roles ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.user_roles ADD COLUMN IF NOT EXISTS "role" public.app_role;
ALTER TABLE public.user_roles ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.user_staking_pools (
  "admin_notes" text,
  "apy_rate" numeric DEFAULT 0,
  "balance" numeric DEFAULT 0,
  "created_at" timestamp with time zone DEFAULT now(),
  "declined_at" timestamp with time zone,
  "declined_by" uuid,
  "dynamic_apy" numeric,
  "enhanced_pool_id" uuid,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "is_enhanced_pool" boolean DEFAULT false,
  "last_reward_date" date,
  "lock_end_date" timestamp with time zone,
  "network_efficiency" numeric(3,2) DEFAULT 1.0,
  "original_stake_amount" numeric,
  "pool_type" text NOT NULL,
  "rewards_earned" numeric DEFAULT 0,
  "stake_duration_months" integer DEFAULT 3,
  "staked_amount" numeric DEFAULT 0,
  "status" text DEFAULT 'active'::text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now(),
  "user_id" uuid NOT NULL,
  CONSTRAINT user_staking_pools_pkey PRIMARY KEY (id)
);
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "admin_notes" text;
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "apy_rate" numeric DEFAULT 0;
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "balance" numeric DEFAULT 0;
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "declined_at" timestamp with time zone;
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "declined_by" uuid;
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "dynamic_apy" numeric;
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "enhanced_pool_id" uuid;
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "is_enhanced_pool" boolean DEFAULT false;
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "last_reward_date" date;
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "lock_end_date" timestamp with time zone;
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "network_efficiency" numeric(3,2) DEFAULT 1.0;
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "original_stake_amount" numeric;
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "pool_type" text;
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "rewards_earned" numeric DEFAULT 0;
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "stake_duration_months" integer DEFAULT 3;
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "staked_amount" numeric DEFAULT 0;
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'active'::text;
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.user_staking_pools ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.user_str_shares (
  "balance" numeric DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "locked_balance" numeric DEFAULT 0 NOT NULL,
  "source_application_id" uuid,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  "vesting_end_date" timestamp with time zone,
  "wnft_shares" numeric DEFAULT 0 NOT NULL,
  CONSTRAINT user_str_shares_pkey PRIMARY KEY (id)
);
ALTER TABLE public.user_str_shares ADD COLUMN IF NOT EXISTS "balance" numeric DEFAULT 0;
ALTER TABLE public.user_str_shares ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.user_str_shares ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.user_str_shares ADD COLUMN IF NOT EXISTS "locked_balance" numeric DEFAULT 0;
ALTER TABLE public.user_str_shares ADD COLUMN IF NOT EXISTS "source_application_id" uuid;
ALTER TABLE public.user_str_shares ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.user_str_shares ADD COLUMN IF NOT EXISTS "user_id" uuid;
ALTER TABLE public.user_str_shares ADD COLUMN IF NOT EXISTS "vesting_end_date" timestamp with time zone;
ALTER TABLE public.user_str_shares ADD COLUMN IF NOT EXISTS "wnft_shares" numeric DEFAULT 0;
CREATE TABLE IF NOT EXISTS public.user_wallets (
  "arss_balance" numeric(18,8) DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "total_earned" numeric(18,8) DEFAULT 0 NOT NULL,
  "total_spent" numeric(18,8) DEFAULT 0 NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  "wallet_address" text NOT NULL,
  CONSTRAINT user_wallets_pkey PRIMARY KEY (id)
);
ALTER TABLE public.user_wallets ADD COLUMN IF NOT EXISTS "arss_balance" numeric(18,8) DEFAULT 0;
ALTER TABLE public.user_wallets ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.user_wallets ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.user_wallets ADD COLUMN IF NOT EXISTS "total_earned" numeric(18,8) DEFAULT 0;
ALTER TABLE public.user_wallets ADD COLUMN IF NOT EXISTS "total_spent" numeric(18,8) DEFAULT 0;
ALTER TABLE public.user_wallets ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.user_wallets ADD COLUMN IF NOT EXISTS "user_id" uuid;
ALTER TABLE public.user_wallets ADD COLUMN IF NOT EXISTS "wallet_address" text;
CREATE TABLE IF NOT EXISTS public.vesting_tokens (
  "amount" numeric DEFAULT 0 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "metadata" jsonb,
  "released_at" timestamp with time zone,
  "released_to_staking_pool_id" uuid,
  "source" text DEFAULT 'voucher'::text NOT NULL,
  "source_id" uuid,
  "status" text DEFAULT 'vesting'::text NOT NULL,
  "token_type" text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  "vesting_end_date" timestamp with time zone NOT NULL,
  "vesting_months" integer DEFAULT 6 NOT NULL,
  "vesting_start_date" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT vesting_tokens_pkey PRIMARY KEY (id)
);
ALTER TABLE public.vesting_tokens ADD COLUMN IF NOT EXISTS "amount" numeric DEFAULT 0;
ALTER TABLE public.vesting_tokens ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.vesting_tokens ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.vesting_tokens ADD COLUMN IF NOT EXISTS "metadata" jsonb;
ALTER TABLE public.vesting_tokens ADD COLUMN IF NOT EXISTS "released_at" timestamp with time zone;
ALTER TABLE public.vesting_tokens ADD COLUMN IF NOT EXISTS "released_to_staking_pool_id" uuid;
ALTER TABLE public.vesting_tokens ADD COLUMN IF NOT EXISTS "source" text DEFAULT 'voucher'::text;
ALTER TABLE public.vesting_tokens ADD COLUMN IF NOT EXISTS "source_id" uuid;
ALTER TABLE public.vesting_tokens ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'vesting'::text;
ALTER TABLE public.vesting_tokens ADD COLUMN IF NOT EXISTS "token_type" text;
ALTER TABLE public.vesting_tokens ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.vesting_tokens ADD COLUMN IF NOT EXISTS "user_id" uuid;
ALTER TABLE public.vesting_tokens ADD COLUMN IF NOT EXISTS "vesting_end_date" timestamp with time zone;
ALTER TABLE public.vesting_tokens ADD COLUMN IF NOT EXISTS "vesting_months" integer DEFAULT 6;
ALTER TABLE public.vesting_tokens ADD COLUMN IF NOT EXISTS "vesting_start_date" timestamp with time zone DEFAULT now();
CREATE TABLE IF NOT EXISTS public.vip_users (
  "created_at" timestamp with time zone DEFAULT now(),
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "last_checked" timestamp with time zone DEFAULT now(),
  "qualification_type" text NOT NULL,
  "qualified_at" timestamp with time zone DEFAULT now(),
  "total_domains_staked" numeric DEFAULT 0,
  "total_str_staked" numeric DEFAULT 0,
  "updated_at" timestamp with time zone DEFAULT now(),
  "user_id" uuid NOT NULL,
  "vip_status" text DEFAULT 'active'::text NOT NULL,
  CONSTRAINT vip_users_pkey PRIMARY KEY (id)
);
ALTER TABLE public.vip_users ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.vip_users ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.vip_users ADD COLUMN IF NOT EXISTS "last_checked" timestamp with time zone DEFAULT now();
ALTER TABLE public.vip_users ADD COLUMN IF NOT EXISTS "qualification_type" text;
ALTER TABLE public.vip_users ADD COLUMN IF NOT EXISTS "qualified_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.vip_users ADD COLUMN IF NOT EXISTS "total_domains_staked" numeric DEFAULT 0;
ALTER TABLE public.vip_users ADD COLUMN IF NOT EXISTS "total_str_staked" numeric DEFAULT 0;
ALTER TABLE public.vip_users ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.vip_users ADD COLUMN IF NOT EXISTS "user_id" uuid;
ALTER TABLE public.vip_users ADD COLUMN IF NOT EXISTS "vip_status" text DEFAULT 'active'::text;
CREATE TABLE IF NOT EXISTS public.voucher_redemptions (
  "admin_notes" text,
  "amount" text,
  "confirmation_number" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "credited_amount" numeric DEFAULT 0,
  "credited_at" timestamp with time zone,
  "deposit_address" text,
  "email_address" text NOT NULL,
  "full_name" text NOT NULL,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "package_type" text NOT NULL,
  "payment_hash" text,
  "payment_type" text NOT NULL,
  "processed_at" timestamp with time zone,
  "processed_by" uuid,
  "proof_of_payment_url" text,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "str_dome_email" text NOT NULL,
  "str_dome_username" text NOT NULL,
  "token_type" text NOT NULL,
  "tokens_credited" boolean DEFAULT false,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  CONSTRAINT voucher_redemptions_pkey PRIMARY KEY (id)
);
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "admin_notes" text;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "amount" text;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "confirmation_number" text;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "credited_amount" numeric DEFAULT 0;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "credited_at" timestamp with time zone;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "deposit_address" text;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "email_address" text;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "full_name" text;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "package_type" text;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "payment_hash" text;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "payment_type" text;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "processed_at" timestamp with time zone;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "processed_by" uuid;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "proof_of_payment_url" text;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "str_dome_email" text;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "str_dome_username" text;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "token_type" text;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "tokens_credited" boolean DEFAULT false;
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.voucher_redemptions ADD COLUMN IF NOT EXISTS "user_id" uuid;
CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  "amount" numeric NOT NULL,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "failure_reason" text,
  "from_address" text NOT NULL,
  "from_user_id" uuid,
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "metadata" jsonb DEFAULT '{}'::jsonb,
  "status" text DEFAULT 'pending'::text NOT NULL,
  "to_address" text NOT NULL,
  "to_user_id" uuid,
  "token_type" text DEFAULT 'str'::text NOT NULL,
  "transaction_hash" text,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT wallet_transactions_pkey PRIMARY KEY (id)
);
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS "amount" numeric;
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS "completed_at" timestamp with time zone;
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS "created_at" timestamp with time zone DEFAULT now();
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS "failure_reason" text;
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS "from_address" text;
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS "from_user_id" uuid;
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS "id" uuid DEFAULT gen_random_uuid();
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS "metadata" jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'pending'::text;
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS "to_address" text;
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS "to_user_id" uuid;
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS "token_type" text DEFAULT 'str'::text;
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS "transaction_hash" text;
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT now();

-- Unique constraints, recovered from ON CONFLICT targets in the history
--
-- Emitted for every table with a conflict target, not just the recovered ones:
-- some of these tables are created by a later migration, and the guard makes
-- the statement a no-op until the table and its columns exist.
DO $$ BEGIN
  ALTER TABLE public.ccoin_banking_profiles ADD CONSTRAINT ccoin_banking_profiles_user_id_key UNIQUE ("user_id");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ccoin_pool_connections ADD CONSTRAINT ccoin_pool_connections_iban_account_id_pool_type_key UNIQUE ("iban_account_id", "pool_type");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.enhanced_staking_pools ADD CONSTRAINT enhanced_staking_pools_name_token_type_duration_months_key UNIQUE ("name", "token_type", "duration_months");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.fiat_wallets ADD CONSTRAINT fiat_wallets_user_id_currency_key UNIQUE ("user_id", "currency");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.governance_votes ADD CONSTRAINT governance_votes_user_id_proposal_id_key UNIQUE ("user_id", "proposal_id");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.iban_accounts ADD CONSTRAINT iban_accounts_user_id_currency_key UNIQUE ("user_id", "currency");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ledger_anchor_chain ADD CONSTRAINT ledger_anchor_chain_chain_id_key UNIQUE ("chain_id");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ledger_asset ADD CONSTRAINT ledger_asset_asset_key UNIQUE ("asset");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ledger_system ADD CONSTRAINT ledger_system_code_key UNIQUE ("code");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.liquidity_pools ADD CONSTRAINT liquidity_pools_pool_symbol_key UNIQUE ("pool_symbol");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.pool_access ADD CONSTRAINT pool_access_user_id_key UNIQUE ("user_id");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.prepaid_cards ADD CONSTRAINT prepaid_cards_user_id_network_card_type_key UNIQUE ("user_id", "network", "card_type");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.prepaid_cards ADD CONSTRAINT prepaid_cards_user_id_network_physical_card_key UNIQUE ("user_id", "network", "physical_card");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.profiles ADD CONSTRAINT profiles_user_id_key UNIQUE ("user_id");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.safe_admins ADD CONSTRAINT safe_admins_user_id_key UNIQUE ("user_id");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.secure ADD CONSTRAINT secure_user_id_key UNIQUE ("user_id");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.storage ADD CONSTRAINT storage_id_key UNIQUE ("id");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_personal_data_encrypted ADD CONSTRAINT user_personal_data_encrypted_user_id_key UNIQUE ("user_id");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_profile_addendum ADD CONSTRAINT user_profile_addendum_user_id_key UNIQUE ("user_id");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_profiles ADD CONSTRAINT user_profiles_user_id_key UNIQUE ("user_id");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_user_id_role_key UNIQUE ("user_id", "role");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_staking_pools ADD CONSTRAINT user_staking_pools_user_id_pool_type_key UNIQUE ("user_id", "pool_type");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_staking_pools ADD CONSTRAINT user_staking_pools_user_id_pool_type_stake_duration_months_key UNIQUE ("user_id", "pool_type", "stake_duration_months");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_wallet_security ADD CONSTRAINT user_wallet_security_user_id_key UNIQUE ("user_id");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.v2_accounts ADD CONSTRAINT v2_accounts_user_id_key UNIQUE ("user_id");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.vip_users ADD CONSTRAINT vip_users_user_id_key UNIQUE ("user_id");
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;

-- UNIQUE constraints, copied from production (scripts/schema-facts.json)
DO $$ BEGIN
  ALTER TABLE public.pending_balance_locks ADD CONSTRAINT pending_balance_locks_transaction_id_key UNIQUE (transaction_id);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.arx_club_members ADD CONSTRAINT arx_club_members_user_id_key UNIQUE (user_id);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ccoin_banking_profiles ADD CONSTRAINT ccoin_banking_profiles_user_id_key UNIQUE (user_id);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.crypto_wallets ADD CONSTRAINT crypto_wallets_user_id_token_type_key UNIQUE (user_id, token_type);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.fiat_transactions ADD CONSTRAINT fiat_transactions_tx_id_key UNIQUE (tx_id);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.fiat_wallets ADD CONSTRAINT fiat_wallets_user_id_currency_key UNIQUE (user_id, currency);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.github_integrations ADD CONSTRAINT github_integrations_user_id_key UNIQUE (user_id);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.iban_accounts ADD CONSTRAINT iban_accounts_iban_key UNIQUE (iban);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.pending_profile_changes ADD CONSTRAINT pending_profile_changes_confirmation_token_key UNIQUE (confirmation_token);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.praeco_peers ADD CONSTRAINT praeco_peers_node_id_key UNIQUE (node_id);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.profiles ADD CONSTRAINT profiles_user_id_key UNIQUE (user_id);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.seed_str_affiliates ADD CONSTRAINT seed_str_affiliates_affiliate_code_key UNIQUE (affiliate_code);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.staking_data_cache ADD CONSTRAINT staking_data_cache_cache_key_key UNIQUE (cache_key);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.str_domains ADD CONSTRAINT str_domains_domain_name_unique UNIQUE (domain_name);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.str_domains ADD CONSTRAINT unique_domain_name UNIQUE (domain_name);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_profiles ADD CONSTRAINT user_profiles_referral_code_key UNIQUE (referral_code);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_profiles ADD CONSTRAINT user_profiles_user_id_key UNIQUE (user_id);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_user_id_role_key UNIQUE (user_id, role);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_str_shares ADD CONSTRAINT user_str_shares_user_id_key UNIQUE (user_id);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_wallets ADD CONSTRAINT user_wallets_user_id_key UNIQUE (user_id);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_wallets ADD CONSTRAINT user_wallets_wallet_address_key UNIQUE (wallet_address);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.vip_users ADD CONSTRAINT vip_users_user_id_key UNIQUE (user_id);
EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;
END $$;

-- CHECK constraints, copied from production (scripts/schema-facts.json)
DO $$ BEGIN
  ALTER TABLE public.pending_balance_locks ADD CONSTRAINT pending_balance_locks_locked_amount_check CHECK ((locked_amount > (0)::numeric));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.airdrop_registrations ADD CONSTRAINT airdrop_registrations_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ccoin_bank_applications ADD CONSTRAINT ccoin_bank_applications_account_type_check CHECK ((account_type = ANY (ARRAY['personal'::text, 'business'::text, 'corporate'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ccoin_banking_profiles ADD CONSTRAINT ccoin_banking_profiles_account_type_check CHECK ((account_type = ANY (ARRAY['personal'::text, 'business'::text, 'corporate'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.crypto_wallets ADD CONSTRAINT crypto_wallets_available_balance_check CHECK ((available_balance >= (0)::numeric));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.crypto_wallets ADD CONSTRAINT crypto_wallets_balance_check CHECK ((balance >= (0)::numeric));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.crypto_wallets ADD CONSTRAINT crypto_wallets_held_balance_check CHECK ((held_balance >= (0)::numeric));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.crypto_wallets ADD CONSTRAINT crypto_wallets_token_type_check CHECK ((token_type = ANY (ARRAY['CCOS'::text, 'STARW'::text, 'ARSS'::text, 'HEX'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.domain_marketplace_bids ADD CONSTRAINT domain_marketplace_bids_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'rejected'::text, 'outbid'::text, 'expired'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.domain_marketplace_listings ADD CONSTRAINT domain_marketplace_listings_domain_type_check CHECK ((domain_type = ANY (ARRAY['standard'::text, 'premium'::text, 'business'::text, 'brand'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.domain_marketplace_listings ADD CONSTRAINT domain_marketplace_listings_listing_type_check CHECK ((listing_type = ANY (ARRAY['buy_now'::text, 'auction'::text, 'both'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.domain_marketplace_listings ADD CONSTRAINT domain_marketplace_listings_status_check CHECK ((status = ANY (ARRAY['active'::text, 'pending_payment'::text, 'reserved'::text, 'sold'::text, 'cancelled'::text, 'suspended'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.domain_marketplace_transactions ADD CONSTRAINT domain_marketplace_transactions_escrow_status_check CHECK ((escrow_status = ANY (ARRAY['pending'::text, 'payment_received'::text, 'admin_approved'::text, 'released'::text, 'disputed'::text, 'refunded'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.domain_marketplace_transactions ADD CONSTRAINT domain_marketplace_transactions_sale_type_check CHECK ((sale_type = ANY (ARRAY['buy_now'::text, 'auction'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.domain_marketplace_transactions ADD CONSTRAINT domain_marketplace_transactions_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'completed'::text, 'cancelled'::text, 'refunded'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.fiat_transactions ADD CONSTRAINT fiat_transactions_amount_check CHECK ((amount > (0)::numeric));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.fiat_transactions ADD CONSTRAINT fiat_transactions_currency_check CHECK ((currency = ANY (ARRAY['EUR'::text, 'CHF'::text, 'GBP'::text, 'USD'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.fiat_transactions ADD CONSTRAINT fiat_transactions_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'completed'::text, 'failed'::text, 'escrowed'::text, 'released'::text, 'cancelled'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.fiat_transactions ADD CONSTRAINT fiat_transactions_transfer_type_check CHECK ((transfer_type = ANY (ARRAY['network'::text, 'account'::text, 'email'::text, 'sepa'::text, 'uk_payment'::text, 'wire'::text, 'swift'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.fiat_wallets ADD CONSTRAINT fiat_wallets_available_balance_check CHECK ((available_balance >= (0)::numeric));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.fiat_wallets ADD CONSTRAINT fiat_wallets_balance_check CHECK ((balance >= (0)::numeric));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.fiat_wallets ADD CONSTRAINT fiat_wallets_currency_check CHECK ((currency = ANY (ARRAY['EUR'::text, 'CHF'::text, 'GBP'::text, 'USD'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.fiat_wallets ADD CONSTRAINT fiat_wallets_held_balance_check CHECK ((held_balance >= (0)::numeric));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.governance_proposals ADD CONSTRAINT governance_proposals_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.guardian_flash_alerts ADD CONSTRAINT guardian_flash_alerts_alert_type_check CHECK ((alert_type = ANY (ARRAY['crash_warning'::text, 'flash_sell'::text, 'flash_buy'::text, 'margin_breach'::text, 'liquidity_warning'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.guardian_flash_alerts ADD CONSTRAINT guardian_flash_alerts_severity_check CHECK ((severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.guardian_flash_alerts ADD CONSTRAINT guardian_flash_alerts_status_check CHECK ((status = ANY (ARRAY['active'::text, 'acknowledged'::text, 'resolved'::text, 'dismissed'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.guardian_invitations ADD CONSTRAINT guardian_invitations_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'expired'::text, 'revoked'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.guardian_invitations ADD CONSTRAINT invitation_target CHECK (((invited_email IS NOT NULL) OR (invited_str_domain IS NOT NULL)));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.iban_accounts ADD CONSTRAINT iban_accounts_account_category_check CHECK ((account_category = ANY (ARRAY['personal'::text, 'business'::text, 'corporate'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.iban_accounts ADD CONSTRAINT iban_accounts_user_id_check CHECK ((user_id IS NOT NULL));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ipo_listing_requests ADD CONSTRAINT ipo_listing_requests_number_of_shares_check CHECK ((number_of_shares > 0));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ipo_listing_requests ADD CONSTRAINT ipo_listing_requests_receiving_currency_check CHECK ((receiving_currency = ANY (ARRAY['USD'::text, 'EUR'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ipo_listing_requests ADD CONSTRAINT ipo_listing_requests_share_type_check CHECK ((share_type = ANY (ARRAY['seed_private_sale'::text, 'ssi'::text, 'pre_ipo'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ipo_listing_requests ADD CONSTRAINT ipo_listing_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'completed'::text, 'suspended'::text, 'more_info_requested'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.member_support_tickets ADD CONSTRAINT member_support_tickets_category_check CHECK ((category = ANY (ARRAY['profile_security'::text, 'voucher'::text, 'staking'::text, 'banking'::text, 'other'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.member_support_tickets ADD CONSTRAINT member_support_tickets_severity_check CHECK ((severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.member_support_tickets ADD CONSTRAINT member_support_tickets_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'resolved'::text, 'closed'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.merchant_business_ibans ADD CONSTRAINT merchant_business_ibans_currency_check CHECK ((currency = ANY (ARRAY['EUR'::text, 'USD'::text, 'CHF'::text, 'GBP'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.merchant_business_ibans ADD CONSTRAINT merchant_business_ibans_status_check CHECK ((status = ANY (ARRAY['active'::text, 'frozen'::text, 'closed'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.merchant_products ADD CONSTRAINT merchant_products_crypto_currency_check CHECK ((crypto_currency = ANY (ARRAY['STR'::text, 'wSTR'::text, 'CCOS'::text, 'ARSS'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.merchant_products ADD CONSTRAINT merchant_products_price_check CHECK ((price >= (0)::numeric));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.pending_profile_changes ADD CONSTRAINT pending_profile_changes_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'email_confirmed'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.prepaid_cards ADD CONSTRAINT prepaid_cards_card_status_check CHECK ((card_status = ANY (ARRAY['active'::text, 'pending'::text, 'blocked'::text, 'expired'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.prepaid_cards ADD CONSTRAINT prepaid_cards_shipping_status_check CHECK ((shipping_status = ANY (ARRAY['pending'::text, 'shipped'::text, 'delivered'::text, NULL::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.seed_str_applications ADD CONSTRAINT seed_str_applications_payment_status_check CHECK ((payment_status = ANY (ARRAY['awaiting_payment'::text, 'payment_submitted'::text, 'payment_verified'::text, 'payment_declined'::text, 'payment_expired'::text, 'cancelled'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.staking_requests ADD CONSTRAINT staking_requests_duration_check CHECK ((duration_months = ANY (ARRAY[3, 6, 9, 12, 24, 36, 48])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.staking_requests ADD CONSTRAINT staking_requests_pool_type_check CHECK ((pool_type = ANY (ARRAY['str'::text, 'ccos'::text, 'domain'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.staking_requests ADD CONSTRAINT staking_requests_request_type_check CHECK ((request_type = ANY (ARRAY['stake'::text, 'unstake'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.staking_requests ADD CONSTRAINT staking_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.staking_rewards_distribution ADD CONSTRAINT valid_apy CHECK (((calculated_apy > (0)::numeric) AND (calculated_apy <= (100)::numeric)));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.staking_rewards_distribution ADD CONSTRAINT valid_efficiency CHECK (((network_efficiency > (0)::numeric) AND (network_efficiency <= 2.0)));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.staking_rewards_distribution ADD CONSTRAINT valid_stake_amount CHECK (((stake_amount >= (1000)::numeric) AND (stake_amount <= (10000000)::numeric)));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.str_domains ADD CONSTRAINT str_domains_domain_name_format CHECK (((domain_name IS NOT NULL) AND (length(domain_name) >= 3) AND (length(domain_name) <= 63)));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.str_domains ADD CONSTRAINT str_domains_domain_type_check CHECK ((domain_type = ANY (ARRAY['personal'::text, 'business'::text, 'premium'::text, 'brand'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.str_domains ADD CONSTRAINT str_domains_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'minted'::text, 'rejected'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.str_dome_requests ADD CONSTRAINT str_dome_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'fulfilled'::text, 'cancelled'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_staking_pools ADD CONSTRAINT user_staking_pools_pool_type_check CHECK ((pool_type = ANY (ARRAY['str'::text, 'ccos'::text, 'domain'::text, 'arss'::text, 'wstr'::text, 'estr'::text, 'str_stable'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_staking_pools ADD CONSTRAINT user_staking_pools_status_check CHECK ((status = ANY (ARRAY['active'::text, 'declined'::text, 'suspended'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.vesting_tokens ADD CONSTRAINT vesting_tokens_status_check CHECK ((status = ANY (ARRAY['vesting'::text, 'vested'::text, 'staked'::text, 'cancelled'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.vesting_tokens ADD CONSTRAINT vesting_tokens_token_type_check CHECK ((token_type = ANY (ARRAY['str'::text, 'arss'::text, 'ccos'::text, 'starw'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.voucher_redemptions ADD CONSTRAINT voucher_redemptions_payment_type_check CHECK ((payment_type = ANY (ARRAY['crypto'::text, 'bank'::text, 'card'::text, 'voucher'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.voucher_redemptions ADD CONSTRAINT voucher_redemptions_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'approved'::text, 'rejected'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.voucher_redemptions ADD CONSTRAINT voucher_redemptions_token_type_check CHECK ((token_type = ANY (ARRAY['str'::text, 'ccos'::text, 'arss'::text, 'vanquish'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.wallet_transactions ADD CONSTRAINT valid_addresses CHECK ((from_address <> to_address));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.wallet_transactions ADD CONSTRAINT wallet_transactions_amount_check CHECK ((amount > (0)::numeric));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.wallet_transactions ADD CONSTRAINT wallet_transactions_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'completed'::text, 'failed'::text, 'cancelled'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;
END $$;

-- Row level security
ALTER TABLE public.ai_usage_sessions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.ai_usage_sessions
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.capacity_sharing ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.capacity_sharing
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.learning_contributions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.learning_contributions
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.pending_balance_locks ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.pending_balance_locks
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.str_domain_connections ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.str_domain_connections
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.airdrop_registrations ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.airdrop_registrations
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.arss_transactions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.arss_transactions
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.arx_audit_trail ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered readable" ON public.arx_audit_trail
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.arx_club_members ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.arx_club_members
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.arx_treasury_transactions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered readable" ON public.arx_treasury_transactions
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.auth_attempts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.auth_attempts
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.ccoin_bank_applications ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.ccoin_bank_applications
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.ccoin_banking_profiles ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.ccoin_banking_profiles
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.ccoin_validations ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.ccoin_validations
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.crypto_wallets ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.crypto_wallets
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.currency_exchanges ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.currency_exchanges
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.domain_marketplace_bids ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered readable" ON public.domain_marketplace_bids
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.domain_marketplace_listings ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered readable" ON public.domain_marketplace_listings
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.domain_marketplace_transactions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered readable" ON public.domain_marketplace_transactions
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.enhanced_rate_limits ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered readable" ON public.enhanced_rate_limits
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.enhanced_staking_pools ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered readable" ON public.enhanced_staking_pools
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.fiat_transactions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered readable" ON public.fiat_transactions
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.fiat_wallets ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.fiat_wallets
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.github_integrations ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.github_integrations
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.governance_proposals ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.governance_proposals
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.guardian_flash_alerts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered readable" ON public.guardian_flash_alerts
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.guardian_invitations ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered readable" ON public.guardian_invitations
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.guardian_wallets ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.guardian_wallets
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.iban_accounts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.iban_accounts
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.ipo_listing_requests ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.ipo_listing_requests
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.liquidity_pools ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered readable" ON public.liquidity_pools
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.liquidity_transactions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.liquidity_transactions
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.member_support_tickets ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.member_support_tickets
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.merchant_business_ibans ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.merchant_business_ibans
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.merchant_products ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.merchant_products
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.pending_profile_changes ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.pending_profile_changes
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.praeco_peers ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.praeco_peers
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.prepaid_cards ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.prepaid_cards
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.private_seed_str_applications ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.private_seed_str_applications
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.private_seed_str_audit_log ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.private_seed_str_audit_log
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.profile_changes ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.profile_changes
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.profiles
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.safe_admins ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.safe_admins
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.safe_purchases ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.safe_purchases
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.security_audit_log ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.security_audit_log
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.seed_str_affiliates ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.seed_str_affiliates
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.seed_str_applications ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.seed_str_applications
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.seed_str_audit_log ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.seed_str_audit_log
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.staking_data_cache ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered readable" ON public.staking_data_cache
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.staking_requests ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.staking_requests
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.staking_rewards_distribution ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.staking_rewards_distribution
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.str_domains ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.str_domains
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.str_dome_requests ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.str_dome_requests
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.user_liquidity_positions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.user_liquidity_positions
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.user_messages ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered readable" ON public.user_messages
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.user_profiles
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "own roles are readable" ON public.user_roles
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.user_staking_pools ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.user_staking_pools
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.user_str_shares ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.user_str_shares
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.user_wallets ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.user_wallets
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.vesting_tokens ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.vesting_tokens
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.vip_users ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.vip_users
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.voucher_redemptions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered own select" ON public.voucher_redemptions
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "recovered readable" ON public.wallet_transactions
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Foreign keys
DO $$ BEGIN
  ALTER TABLE public.ai_usage_sessions ADD CONSTRAINT ai_usage_sessions_voucher_id_fkey
    FOREIGN KEY (voucher_id) REFERENCES public.voucher_redemptions(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.capacity_sharing ADD CONSTRAINT capacity_sharing_cancellation_id_fkey
    FOREIGN KEY (cancellation_id) REFERENCES public.ccoin_bank_cancellations(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.learning_contributions ADD CONSTRAINT learning_contributions_pool_id_fkey
    FOREIGN KEY (pool_id) REFERENCES public.liquidity_pools(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.pending_balance_locks ADD CONSTRAINT pending_balance_locks_transaction_id_fkey
    FOREIGN KEY (transaction_id) REFERENCES public.wallet_transactions(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.str_domain_connections ADD CONSTRAINT str_domain_connections_supernode_id_fkey
    FOREIGN KEY (supernode_id) REFERENCES public.supernodes(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.airdrop_registrations ADD CONSTRAINT airdrop_registrations_voucher_id_fkey
    FOREIGN KEY (voucher_id) REFERENCES public.voucher_redemptions(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.arss_transactions ADD CONSTRAINT arss_transactions_event_id_fkey
    FOREIGN KEY (event_id) REFERENCES public.arx_events(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.arx_audit_trail ADD CONSTRAINT arx_audit_trail_event_id_fkey
    FOREIGN KEY (event_id) REFERENCES public.arx_events(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.arx_club_members ADD CONSTRAINT arx_club_members_event_id_fkey
    FOREIGN KEY (event_id) REFERENCES public.arx_events(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.arx_treasury_transactions ADD CONSTRAINT arx_treasury_transactions_pool_id_fkey
    FOREIGN KEY (pool_id) REFERENCES public.arx_treasury_pools(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.auth_attempts ADD CONSTRAINT auth_attempts_application_id_fkey
    FOREIGN KEY (application_id) REFERENCES public.business_domain_applications(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ccoin_bank_applications ADD CONSTRAINT ccoin_bank_applications_cancellation_id_fkey
    FOREIGN KEY (cancellation_id) REFERENCES public.ccoin_bank_cancellations(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ccoin_banking_profiles ADD CONSTRAINT ccoin_banking_profiles_ccoin_card_id_fkey
    FOREIGN KEY (ccoin_card_id) REFERENCES public.prepaid_cards(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ccoin_banking_profiles ADD CONSTRAINT ccoin_banking_profiles_chf_iban_id_fkey
    FOREIGN KEY (chf_iban_id) REFERENCES public.iban_accounts(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ccoin_banking_profiles ADD CONSTRAINT ccoin_banking_profiles_eur_iban_id_fkey
    FOREIGN KEY (eur_iban_id) REFERENCES public.iban_accounts(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ccoin_banking_profiles ADD CONSTRAINT ccoin_banking_profiles_gbp_iban_id_fkey
    FOREIGN KEY (gbp_iban_id) REFERENCES public.iban_accounts(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ccoin_banking_profiles ADD CONSTRAINT ccoin_banking_profiles_visa_card_id_fkey
    FOREIGN KEY (visa_card_id) REFERENCES public.prepaid_cards(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ccoin_validations ADD CONSTRAINT ccoin_validations_reply_to_id_fkey
    FOREIGN KEY (reply_to_id) REFERENCES public.chat_messages(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.crypto_wallets ADD CONSTRAINT crypto_wallets_listing_id_fkey
    FOREIGN KEY (listing_id) REFERENCES public.domain_marketplace_listings(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.currency_exchanges ADD CONSTRAINT currency_exchanges_listing_id_fkey
    FOREIGN KEY (listing_id) REFERENCES public.domain_marketplace_listings(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.domain_marketplace_bids ADD CONSTRAINT domain_marketplace_bids_listing_id_fkey
    FOREIGN KEY (listing_id) REFERENCES public.domain_marketplace_listings(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.domain_marketplace_listings ADD CONSTRAINT domain_marketplace_listings_accepted_bid_id_fkey
    FOREIGN KEY (accepted_bid_id) REFERENCES public.domain_marketplace_bids(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.domain_marketplace_listings ADD CONSTRAINT domain_marketplace_listings_domain_id_fkey
    FOREIGN KEY (domain_id) REFERENCES public.str_domains(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.domain_marketplace_transactions ADD CONSTRAINT domain_marketplace_transactions_domain_id_fkey
    FOREIGN KEY (domain_id) REFERENCES public.str_domains(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.domain_marketplace_transactions ADD CONSTRAINT domain_marketplace_transactions_listing_id_fkey
    FOREIGN KEY (listing_id) REFERENCES public.domain_marketplace_listings(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.enhanced_rate_limits ADD CONSTRAINT enhanced_rate_limits_proposal_id_fkey
    FOREIGN KEY (proposal_id) REFERENCES public.governance_proposals(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.enhanced_staking_pools ADD CONSTRAINT enhanced_staking_pools_proposal_id_fkey
    FOREIGN KEY (proposal_id) REFERENCES public.governance_proposals(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.fiat_transactions ADD CONSTRAINT fiat_transactions_proposal_id_fkey
    FOREIGN KEY (proposal_id) REFERENCES public.governance_proposals(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.fiat_wallets ADD CONSTRAINT fiat_wallets_proposal_id_fkey
    FOREIGN KEY (proposal_id) REFERENCES public.governance_proposals(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.github_integrations ADD CONSTRAINT github_integrations_proposal_id_fkey
    FOREIGN KEY (proposal_id) REFERENCES public.governance_proposals(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.governance_proposals ADD CONSTRAINT governance_proposals_proposal_id_fkey
    FOREIGN KEY (proposal_id) REFERENCES public.governance_proposals(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.guardian_flash_alerts ADD CONSTRAINT guardian_flash_alerts_wallet_id_fkey
    FOREIGN KEY (wallet_id) REFERENCES public.guardian_wallets(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.guardian_invitations ADD CONSTRAINT guardian_invitations_wallet_id_fkey
    FOREIGN KEY (wallet_id) REFERENCES public.guardian_wallets(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.guardian_wallets ADD CONSTRAINT guardian_wallets_wallet_id_fkey
    FOREIGN KEY (wallet_id) REFERENCES public.guardian_wallets(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.iban_accounts ADD CONSTRAINT iban_accounts_invoice_id_fkey
    FOREIGN KEY (invoice_id) REFERENCES public.business_invoices(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.ipo_listing_requests ADD CONSTRAINT ipo_listing_requests_pool_id_fkey
    FOREIGN KEY (pool_id) REFERENCES public.liquidity_pools(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.liquidity_pools ADD CONSTRAINT liquidity_pools_pool_id_fkey
    FOREIGN KEY (pool_id) REFERENCES public.liquidity_pools(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.liquidity_transactions ADD CONSTRAINT liquidity_transactions_pool_id_fkey
    FOREIGN KEY (pool_id) REFERENCES public.liquidity_pools(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.member_support_tickets ADD CONSTRAINT member_support_tickets_business_domain_id_fkey
    FOREIGN KEY (business_domain_id) REFERENCES public.business_domains(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.merchant_business_ibans ADD CONSTRAINT merchant_business_ibans_merchant_id_fkey
    FOREIGN KEY (merchant_id) REFERENCES public.merchant_accounts(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.merchant_products ADD CONSTRAINT merchant_products_merchant_id_fkey
    FOREIGN KEY (merchant_id) REFERENCES public.merchant_accounts(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.pending_profile_changes ADD CONSTRAINT pending_profile_changes_merchant_id_fkey
    FOREIGN KEY (merchant_id) REFERENCES public.merchant_accounts(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.pending_profile_changes ADD CONSTRAINT pending_profile_changes_product_id_fkey
    FOREIGN KEY (product_id) REFERENCES public.merchant_products(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.pending_profile_changes ADD CONSTRAINT pending_profile_changes_product_id_fkey
    FOREIGN KEY (product_id) REFERENCES public.public_product_catalog(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.praeco_peers ADD CONSTRAINT praeco_peers_application_id_fkey
    FOREIGN KEY (application_id) REFERENCES public.private_seed_str_applications(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.prepaid_cards ADD CONSTRAINT prepaid_cards_application_id_fkey
    FOREIGN KEY (application_id) REFERENCES public.private_seed_str_applications(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.private_seed_str_applications ADD CONSTRAINT private_seed_str_applications_application_id_fkey
    FOREIGN KEY (application_id) REFERENCES public.private_seed_str_applications(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.private_seed_str_audit_log ADD CONSTRAINT private_seed_str_audit_log_application_id_fkey
    FOREIGN KEY (application_id) REFERENCES public.private_seed_str_applications(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.profile_changes ADD CONSTRAINT profile_changes_affiliate_id_fkey
    FOREIGN KEY (affiliate_id) REFERENCES public.seed_str_affiliates(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.profiles ADD CONSTRAINT profiles_affiliate_id_fkey
    FOREIGN KEY (affiliate_id) REFERENCES public.seed_str_affiliates(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.safe_admins ADD CONSTRAINT safe_admins_affiliate_id_fkey
    FOREIGN KEY (affiliate_id) REFERENCES public.seed_str_affiliates(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.safe_purchases ADD CONSTRAINT safe_purchases_affiliate_id_fkey
    FOREIGN KEY (affiliate_id) REFERENCES public.seed_str_affiliates(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.security_audit_log ADD CONSTRAINT security_audit_log_affiliate_id_fkey
    FOREIGN KEY (affiliate_id) REFERENCES public.seed_str_affiliates(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.seed_str_affiliates ADD CONSTRAINT seed_str_affiliates_affiliate_id_fkey
    FOREIGN KEY (affiliate_id) REFERENCES public.seed_str_affiliates(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.seed_str_applications ADD CONSTRAINT seed_str_applications_affiliate_id_fkey
    FOREIGN KEY (affiliate_id) REFERENCES public.seed_str_affiliates(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.seed_str_audit_log ADD CONSTRAINT seed_str_audit_log_application_id_fkey
    FOREIGN KEY (application_id) REFERENCES public.seed_str_applications(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.staking_data_cache ADD CONSTRAINT staking_data_cache_pool_id_fkey
    FOREIGN KEY (pool_id) REFERENCES public.enhanced_staking_pools(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.staking_requests ADD CONSTRAINT staking_requests_pool_id_fkey
    FOREIGN KEY (pool_id) REFERENCES public.enhanced_staking_pools(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.staking_rewards_distribution ADD CONSTRAINT staking_rewards_distribution_pool_id_fkey
    FOREIGN KEY (pool_id) REFERENCES public.enhanced_staking_pools(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.str_domains ADD CONSTRAINT str_domains_supernode_id_fkey
    FOREIGN KEY (supernode_id) REFERENCES public.supernodes(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.str_dome_requests ADD CONSTRAINT str_dome_requests_supernode_id_fkey
    FOREIGN KEY (supernode_id) REFERENCES public.supernodes(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_liquidity_positions ADD CONSTRAINT user_liquidity_positions_pool_id_fkey
    FOREIGN KEY (pool_id) REFERENCES public.liquidity_pools(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_messages ADD CONSTRAINT user_messages_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES public.user_profiles(user_id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_profiles ADD CONSTRAINT user_profiles_enhanced_pool_id_fkey
    FOREIGN KEY (enhanced_pool_id) REFERENCES public.enhanced_staking_pools(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_enhanced_pool_id_fkey
    FOREIGN KEY (enhanced_pool_id) REFERENCES public.enhanced_staking_pools(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_staking_pools ADD CONSTRAINT user_staking_pools_enhanced_pool_id_fkey
    FOREIGN KEY (enhanced_pool_id) REFERENCES public.enhanced_staking_pools(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_str_shares ADD CONSTRAINT user_str_shares_source_application_id_fkey
    FOREIGN KEY (source_application_id) REFERENCES public.seed_str_applications(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_wallets ADD CONSTRAINT user_wallets_account_id_fkey
    FOREIGN KEY (account_id) REFERENCES public.v2_accounts(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.user_wallets ADD CONSTRAINT user_wallets_duplicate_of_fkey
    FOREIGN KEY (duplicate_of) REFERENCES public.v2_asset_claims(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.vesting_tokens ADD CONSTRAINT vesting_tokens_voucher_id_fkey
    FOREIGN KEY (voucher_id) REFERENCES public.voucher_redemptions(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.vip_users ADD CONSTRAINT vip_users_voucher_id_fkey
    FOREIGN KEY (voucher_id) REFERENCES public.voucher_redemptions(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.voucher_redemptions ADD CONSTRAINT voucher_redemptions_founder_position_id_fkey
    FOREIGN KEY (founder_position_id) REFERENCES public.founder_positions(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE public.wallet_transactions ADD CONSTRAINT wallet_transactions_founder_position_id_fkey
    FOREIGN KEY (founder_position_id) REFERENCES public.founder_positions(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;
END $$;
