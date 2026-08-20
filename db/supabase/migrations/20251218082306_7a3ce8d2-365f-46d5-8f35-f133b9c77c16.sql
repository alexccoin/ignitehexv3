-- Step 1: Drop FK constraint
ALTER TABLE user_profile_addendum DROP CONSTRAINT IF EXISTS fk_addendum_user;

-- Step 2: Create temp mapping of old user_id to new auth user id
CREATE TEMP TABLE user_id_fix_mapping AS
SELECT up.user_id as old_user_id, au.id as new_user_id, up.id as profile_id
FROM user_profiles up
JOIN auth.users au ON LOWER(up.email_address) = LOWER(au.email);

-- Step 3: Update user_profile_addendum with new user_ids
UPDATE user_profile_addendum upa
SET user_id = m.new_user_id
FROM user_id_fix_mapping m
WHERE upa.user_id = m.old_user_id;

-- Step 4: Update user_profiles with correct auth user_ids
UPDATE user_profiles up
SET user_id = m.new_user_id
FROM user_id_fix_mapping m
WHERE up.user_id = m.old_user_id;

-- Step 5: Re-add FK constraint
ALTER TABLE user_profile_addendum
ADD CONSTRAINT fk_addendum_user FOREIGN KEY (user_id) REFERENCES user_profiles(user_id);