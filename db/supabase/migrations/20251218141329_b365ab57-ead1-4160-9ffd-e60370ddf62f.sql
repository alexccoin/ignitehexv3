-- Delete invalid pending user: pellumb.mhilli@gmailcom (4517c61d-227a-4d3f-ab03-21dbde11c0f7)

-- Delete from security_audit_log first (blocking FK)
DELETE FROM security_audit_log WHERE user_id = '4517c61d-227a-4d3f-ab03-21dbde11c0f7';

-- Delete from user_profiles if exists
DELETE FROM user_profiles WHERE user_id = '4517c61d-227a-4d3f-ab03-21dbde11c0f7';

-- Delete from user_roles if exists
DELETE FROM user_roles WHERE user_id = '4517c61d-227a-4d3f-ab03-21dbde11c0f7';

-- Delete from any other related tables
DELETE FROM user_wallets WHERE user_id = '4517c61d-227a-4d3f-ab03-21dbde11c0f7';
DELETE FROM fiat_wallets WHERE user_id = '4517c61d-227a-4d3f-ab03-21dbde11c0f7';
DELETE FROM user_staking_pools WHERE user_id = '4517c61d-227a-4d3f-ab03-21dbde11c0f7';
DELETE FROM staking_requests WHERE user_id = '4517c61d-227a-4d3f-ab03-21dbde11c0f7';
DELETE FROM auth_attempts WHERE user_id = '4517c61d-227a-4d3f-ab03-21dbde11c0f7';

-- Delete from auth.users
DELETE FROM auth.users WHERE id = '4517c61d-227a-4d3f-ab03-21dbde11c0f7';