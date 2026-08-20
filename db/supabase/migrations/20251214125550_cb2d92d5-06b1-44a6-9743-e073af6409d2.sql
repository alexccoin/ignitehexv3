-- Fix PUBLIC_DATA_EXPOSURE: Remove public access to governance_proposals
-- Keep only authenticated access to prevent user ID enumeration by unauthenticated users

DROP POLICY IF EXISTS "Public can view proposals" ON governance_proposals;