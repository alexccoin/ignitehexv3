
-- Step 1: Hash any remaining plaintext passwords in founder_positions
SELECT public.hash_existing_position_passwords();

-- Step 2: Replace validate_position_password to ONLY support hashed passwords (no plaintext fallback)
CREATE OR REPLACE FUNCTION public.validate_position_password(position_id uuid, input_password text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  stored_password text;
BEGIN
  SELECT access_password INTO stored_password
  FROM founder_positions
  WHERE id = position_id;
  
  IF stored_password IS NULL THEN
    RETURN FALSE;
  END IF;
  
  -- Only support hashed password verification
  IF stored_password LIKE '$2%' THEN
    RETURN verify_password(input_password, stored_password);
  ELSE
    -- If somehow still plaintext, hash it first then verify
    UPDATE founder_positions 
    SET access_password = hash_password(access_password)
    WHERE id = position_id 
      AND access_password IS NOT NULL 
      AND access_password NOT LIKE '$2%';
    
    -- Re-fetch and verify
    SELECT access_password INTO stored_password
    FROM founder_positions
    WHERE id = position_id;
    
    RETURN verify_password(input_password, stored_password);
  END IF;
END;
$$;

-- Step 3: Add trigger to auto-hash passwords on insert/update
CREATE OR REPLACE FUNCTION public.hash_position_password_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.access_password IS NOT NULL AND NEW.access_password NOT LIKE '$2%' THEN
    NEW.access_password := hash_password(NEW.access_password);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS auto_hash_position_password ON founder_positions;
CREATE TRIGGER auto_hash_position_password
  BEFORE INSERT OR UPDATE OF access_password ON founder_positions
  FOR EACH ROW
  EXECUTE FUNCTION hash_position_password_trigger();
