-- Fix fiat_wallets RLS - only drop the overly permissive policies
-- The proper user/admin policies already exist

DROP POLICY IF EXISTS "System can manage fiat wallets" ON fiat_wallets;
DROP POLICY IF EXISTS "System can update fiat wallets" ON fiat_wallets;