
-- Delete user adam78ag93@gmail (ID: 13f8f7f4-6de9-41a5-a717-42e6798a0d67) who has no profile created

-- Delete from security_audit_log
DELETE FROM security_audit_log WHERE user_id = '13f8f7f4-6de9-41a5-a717-42e6798a0d67';

-- Delete from user_staking_pools
DELETE FROM user_staking_pools WHERE user_id = '13f8f7f4-6de9-41a5-a717-42e6798a0d67';

-- Delete from staking_requests
DELETE FROM staking_requests WHERE user_id = '13f8f7f4-6de9-41a5-a717-42e6798a0d67';

-- Delete from crypto_wallets
DELETE FROM crypto_wallets WHERE user_id = '13f8f7f4-6de9-41a5-a717-42e6798a0d67';

-- Delete from fiat_wallets
DELETE FROM fiat_wallets WHERE user_id = '13f8f7f4-6de9-41a5-a717-42e6798a0d67';

-- Delete from user_wallets
DELETE FROM user_wallets WHERE user_id = '13f8f7f4-6de9-41a5-a717-42e6798a0d67';

-- Delete from user_roles
DELETE FROM user_roles WHERE user_id = '13f8f7f4-6de9-41a5-a717-42e6798a0d67';

-- Delete from auth_attempts
DELETE FROM auth_attempts WHERE user_id = '13f8f7f4-6de9-41a5-a717-42e6798a0d67';

-- Delete from user_profiles
DELETE FROM user_profiles WHERE user_id = '13f8f7f4-6de9-41a5-a717-42e6798a0d67';

-- Finally delete from auth.users
DELETE FROM auth.users WHERE id = '13f8f7f4-6de9-41a5-a717-42e6798a0d67';
