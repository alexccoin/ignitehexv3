-- Fix overly permissive RLS policies on enhanced_rate_limits table
-- This table should ONLY be modified by Edge Functions with service role
-- Regular users should never have direct access to rate limiting data

-- Drop the permissive policies that allow any user to manipulate rate limits
DROP POLICY IF EXISTS "rate_limits_system_insert" ON enhanced_rate_limits;
DROP POLICY IF EXISTS "rate_limits_system_update" ON enhanced_rate_limits;
DROP POLICY IF EXISTS "rate_limits_system_delete" ON enhanced_rate_limits;