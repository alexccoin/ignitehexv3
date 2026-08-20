
-- Step 1: Drop FK constraint on user_profile_addendum
ALTER TABLE user_profile_addendum DROP CONSTRAINT IF EXISTS fk_addendum_user;

-- Step 2: Create a mapping table of old_user_id to new_user_id (which is id)
CREATE TEMP TABLE user_id_mapping AS
SELECT user_id as old_user_id, id as new_user_id
FROM user_profiles
WHERE user_id != id;

-- Step 3: Update user_profile_addendum with new user_ids
UPDATE user_profile_addendum upa
SET user_id = m.new_user_id
FROM user_id_mapping m
WHERE upa.user_id = m.old_user_id;

-- Step 4: Update user_profiles to sync user_id with id
UPDATE user_profiles
SET user_id = id
WHERE user_id != id;

-- Step 5: Re-add the FK constraint
ALTER TABLE user_profile_addendum
ADD CONSTRAINT fk_addendum_user FOREIGN KEY (user_id) REFERENCES user_profiles(user_id);
