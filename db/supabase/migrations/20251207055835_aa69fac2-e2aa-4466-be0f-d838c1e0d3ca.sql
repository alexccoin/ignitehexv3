-- Drop the old function with account_status type to resolve ambiguity
DROP FUNCTION IF EXISTS public.admin_upsert_user_profile_status(UUID, public.account_status, TEXT, TEXT);

-- Also drop any other variations that might exist
DROP FUNCTION IF EXISTS public.admin_upsert_user_profile_status(UUID, TEXT, TEXT);