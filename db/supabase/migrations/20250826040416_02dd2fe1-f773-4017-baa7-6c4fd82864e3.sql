-- Create voucher redemption history table for audit trail
CREATE TABLE voucher_redemption_history (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  voucher_redemption_id UUID NOT NULL,
  status_from TEXT,
  status_to TEXT NOT NULL,
  action_performed TEXT NOT NULL,
  performed_by UUID,
  admin_notes TEXT,
  error_details JSONB,
  metadata JSONB DEFAULT '{}',
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS on voucher history
ALTER TABLE voucher_redemption_history ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for voucher history
CREATE POLICY "Admins can view all voucher history"
ON voucher_redemption_history
FOR SELECT
USING (is_admin(auth.uid()));

CREATE POLICY "System can insert voucher history"
ON voucher_redemption_history
FOR INSERT
WITH CHECK (true);

-- Create voucher error log table for detailed error tracking
CREATE TABLE voucher_error_log (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  voucher_redemption_id UUID,
  error_type TEXT NOT NULL,
  error_message TEXT NOT NULL,
  error_details JSONB,
  stack_trace TEXT,
  user_id UUID,
  performed_by UUID,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS on error log
ALTER TABLE voucher_error_log ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for error log
CREATE POLICY "Admins can view all voucher errors"
ON voucher_error_log
FOR SELECT
USING (is_admin(auth.uid()));

CREATE POLICY "System can insert voucher errors"
ON voucher_error_log
FOR INSERT
WITH CHECK (true);

-- Create comprehensive voucher processing function with full audit trail
CREATE OR REPLACE FUNCTION process_voucher_redemption_with_audit(
  voucher_id UUID,
  new_status TEXT,
  performed_by_user_id UUID,
  admin_notes_param TEXT DEFAULT NULL,
  client_ip INET DEFAULT NULL,
  user_agent_param TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  voucher_record voucher_redemptions%ROWTYPE;
  old_status TEXT;
  result JSONB;
  credit_result NUMERIC;
  error_occurred BOOLEAN := false;
  error_message TEXT;
BEGIN
  -- Start transaction logging
  INSERT INTO voucher_redemption_history (
    voucher_redemption_id,
    status_from,
    status_to,
    action_performed,
    performed_by,
    admin_notes,
    ip_address,
    user_agent,
    metadata
  ) VALUES (
    voucher_id,
    NULL,
    'processing_started',
    'voucher_processing_initiated',
    performed_by_user_id,
    'Processing voucher redemption request',
    client_ip,
    user_agent_param,
    jsonb_build_object('timestamp', now(), 'function', 'process_voucher_redemption_with_audit')
  );

  -- Get current voucher record
  SELECT * INTO voucher_record 
  FROM voucher_redemptions 
  WHERE id = voucher_id;
  
  IF NOT FOUND THEN
    -- Log error
    INSERT INTO voucher_error_log (
      voucher_redemption_id,
      error_type,
      error_message,
      performed_by,
      ip_address,
      user_agent
    ) VALUES (
      voucher_id,
      'voucher_not_found',
      'Voucher redemption not found with ID: ' || voucher_id::text,
      performed_by_user_id,
      client_ip,
      user_agent_param
    );
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'voucher_not_found',
      'message', 'Voucher redemption not found'
    );
  END IF;
  
  old_status := voucher_record.status;
  
  -- Validate status transition
  IF old_status = new_status THEN
    INSERT INTO voucher_error_log (
      voucher_redemption_id,
      error_type,
      error_message,
      error_details,
      performed_by,
      ip_address,
      user_agent
    ) VALUES (
      voucher_id,
      'invalid_status_transition',
      'Attempting to change status from ' || old_status || ' to ' || new_status,
      jsonb_build_object('old_status', old_status, 'new_status', new_status),
      performed_by_user_id,
      client_ip,
      user_agent_param
    );
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'invalid_status_transition',
      'message', 'Status is already ' || old_status
    );
  END IF;
  
  BEGIN
    -- Update voucher status
    UPDATE voucher_redemptions 
    SET 
      status = new_status,
      admin_notes = COALESCE(admin_notes_param, admin_notes),
      processed_by = performed_by_user_id,
      processed_at = CASE WHEN new_status IN ('approved', 'rejected') THEN now() ELSE processed_at END,
      updated_at = now()
    WHERE id = voucher_id;
    
    -- Log successful status change
    INSERT INTO voucher_redemption_history (
      voucher_redemption_id,
      status_from,
      status_to,
      action_performed,
      performed_by,
      admin_notes,
      ip_address,
      user_agent,
      metadata
    ) VALUES (
      voucher_id,
      old_status,
      new_status,
      'status_changed',
      performed_by_user_id,
      admin_notes_param,
      client_ip,
      user_agent_param,
      jsonb_build_object(
        'user_id', voucher_record.user_id,
        'token_type', voucher_record.token_type,
        'package_type', voucher_record.package_type,
        'timestamp', now()
      )
    );
    
    -- If approved, attempt to credit tokens
    IF new_status = 'approved' AND NOT COALESCE(voucher_record.tokens_credited, false) THEN
      BEGIN
        SELECT credit_voucher_tokens(
          voucher_id,
          voucher_record.user_id,
          voucher_record.token_type,
          voucher_record.package_type
        ) INTO credit_result;
        
        -- Log successful token crediting
        INSERT INTO voucher_redemption_history (
          voucher_redemption_id,
          status_from,
          status_to,
          action_performed,
          performed_by,
          admin_notes,
          ip_address,
          user_agent,
          metadata
        ) VALUES (
          voucher_id,
          new_status,
          new_status,
          'tokens_credited',
          performed_by_user_id,
          'Tokens successfully credited: ' || credit_result::text,
          client_ip,
          user_agent_param,
          jsonb_build_object(
            'credited_amount', credit_result,
            'user_id', voucher_record.user_id,
            'token_type', voucher_record.token_type,
            'timestamp', now()
          )
        );
        
      EXCEPTION WHEN OTHERS THEN
        error_occurred := true;
        error_message := SQLERRM;
        
        -- Log token crediting error
        INSERT INTO voucher_error_log (
          voucher_redemption_id,
          error_type,
          error_message,
          error_details,
          user_id,
          performed_by,
          ip_address,
          user_agent
        ) VALUES (
          voucher_id,
          'token_crediting_failed',
          'Failed to credit tokens: ' || error_message,
          jsonb_build_object(
            'user_id', voucher_record.user_id,
            'token_type', voucher_record.token_type,
            'package_type', voucher_record.package_type,
            'error_code', SQLSTATE,
            'timestamp', now()
          ),
          voucher_record.user_id,
          performed_by_user_id,
          client_ip,
          user_agent_param
        );
      END;
    END IF;
    
    -- Build success result
    result := jsonb_build_object(
      'success', true,
      'voucher_id', voucher_id,
      'old_status', old_status,
      'new_status', new_status,
      'tokens_credited', CASE WHEN new_status = 'approved' THEN NOT error_occurred ELSE false END,
      'credited_amount', CASE WHEN new_status = 'approved' AND NOT error_occurred THEN credit_result ELSE 0 END,
      'message', CASE 
        WHEN new_status = 'approved' AND error_occurred THEN 'Voucher approved but token crediting failed'
        WHEN new_status = 'approved' THEN 'Voucher approved and tokens credited successfully'
        ELSE 'Voucher status updated to ' || new_status
      END
    );
    
  EXCEPTION WHEN OTHERS THEN
    error_occurred := true;
    error_message := SQLERRM;
    
    -- Log processing error
    INSERT INTO voucher_error_log (
      voucher_redemption_id,
      error_type,
      error_message,
      error_details,
      user_id,
      performed_by,
      ip_address,
      user_agent
    ) VALUES (
      voucher_id,
      'processing_error',
      'Error processing voucher: ' || error_message,
      jsonb_build_object(
        'old_status', old_status,
        'new_status', new_status,
        'error_code', SQLSTATE,
        'timestamp', now()
      ),
      voucher_record.user_id,
      performed_by_user_id,
      client_ip,
      user_agent_param
    );
    
    result := jsonb_build_object(
      'success', false,
      'error', 'processing_error',
      'message', 'Error processing voucher: ' || error_message
    );
  END;
  
  -- Final audit log entry
  INSERT INTO voucher_redemption_history (
    voucher_redemption_id,
    status_from,
    status_to,
    action_performed,
    performed_by,
    admin_notes,
    ip_address,
    user_agent,
    metadata
  ) VALUES (
    voucher_id,
    old_status,
    CASE WHEN error_occurred THEN old_status ELSE new_status END,
    'processing_completed',
    performed_by_user_id,
    CASE WHEN error_occurred THEN 'Processing completed with errors' ELSE 'Processing completed successfully' END,
    client_ip,
    user_agent_param,
    result
  );
  
  RETURN result;
END;
$$;

-- Create function to get voucher audit trail
CREATE OR REPLACE FUNCTION get_voucher_audit_trail(voucher_id UUID)
RETURNS TABLE(
  id UUID,
  status_from TEXT,
  status_to TEXT,
  action_performed TEXT,
  performed_by UUID,
  performer_email TEXT,
  admin_notes TEXT,
  error_details JSONB,
  metadata JSONB,
  created_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;
  
  RETURN QUERY
  SELECT 
    vrh.id,
    vrh.status_from,
    vrh.status_to,
    vrh.action_performed,
    vrh.performed_by,
    COALESCE(au.email, 'System') as performer_email,
    vrh.admin_notes,
    vrh.error_details,
    vrh.metadata,
    vrh.created_at
  FROM voucher_redemption_history vrh
  LEFT JOIN auth.users au ON vrh.performed_by = au.id
  WHERE vrh.voucher_redemption_id = get_voucher_audit_trail.voucher_id
  ORDER BY vrh.created_at DESC;
END;
$$;