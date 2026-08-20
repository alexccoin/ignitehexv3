-- Update validation functions to use proper hashing with extension schema
CREATE OR REPLACE FUNCTION public.hash_password(plain_password text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
BEGIN
  -- Use pgcrypto from extensions schema for password hashing
  RETURN extensions.crypt(plain_password, extensions.gen_salt('bf', 8));
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_password(plain_password text, hashed_password text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
BEGIN
  -- Use pgcrypto from extensions schema for password verification
  RETURN extensions.crypt(plain_password, hashed_password) = hashed_password;
END;
$$;

-- Update position password validation to use proper hashing
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
  
  -- If no stored password, deny access
  IF stored_password IS NULL THEN
    RETURN FALSE;
  END IF;
  
  -- Check if password is already hashed (starts with $2)
  IF stored_password LIKE '$2%' THEN
    -- Use proper hash verification
    RETURN verify_password(input_password, stored_password);
  ELSE
    -- Legacy plain text comparison for existing data
    RETURN stored_password = input_password;
  END IF;
END;
$$;

-- Create function to hash existing passwords
CREATE OR REPLACE FUNCTION public.hash_existing_position_passwords()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE founder_positions 
  SET access_password = hash_password(access_password)
  WHERE access_password IS NOT NULL 
    AND access_password NOT LIKE '$2%'; -- Only hash if not already hashed
END;
$$;

-- Add RLS policy for security audit logs
CREATE POLICY "System can insert security logs" 
ON security_audit_log 
FOR INSERT 
WITH CHECK (true);

-- Add input validation trigger for founder positions
CREATE OR REPLACE FUNCTION public.validate_founder_position_input()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Validate required fields
  IF NEW.user_id IS NULL THEN
    RAISE EXCEPTION 'User ID is required';
  END IF;
  
  -- Validate BTC amounts are positive
  IF NEW.input_btc_amount IS NOT NULL AND NEW.input_btc_amount <= 0 THEN
    RAISE EXCEPTION 'Input BTC amount must be positive';
  END IF;
  
  -- Validate USD values are reasonable
  IF NEW.current_usd_value IS NOT NULL AND (NEW.current_usd_value <= 0 OR NEW.current_usd_value > 10000000) THEN
    RAISE EXCEPTION 'USD value out of reasonable range';
  END IF;
  
  -- Hash password if provided and not already hashed
  IF NEW.access_password IS NOT NULL AND NEW.access_password NOT LIKE '$2%' THEN
    NEW.access_password := hash_password(NEW.access_password);
  END IF;
  
  RETURN NEW;
END;
$$;

CREATE TRIGGER validate_founder_position_trigger
BEFORE INSERT OR UPDATE ON founder_positions
FOR EACH ROW EXECUTE FUNCTION validate_founder_position_input();