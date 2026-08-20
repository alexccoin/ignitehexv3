-- Fix search_path security issue in notify_admin_of_critical_error function
CREATE OR REPLACE FUNCTION notify_admin_of_critical_error()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Only notify for critical error types
  IF NEW.error_type IN ('database_error', 'api_error') THEN
    -- Insert notification for admins (using user_messages table)
    INSERT INTO public.user_messages (
      sender_id,
      recipient_id,
      subject,
      message,
      message_type,
      metadata
    )
    SELECT 
      NEW.user_id,
      ur.user_id,
      'CRITICAL_ERROR',
      'Critical error occurred: ' || NEW.error_message,
      'system',
      jsonb_build_object(
        'error_id', NEW.id,
        'error_type', NEW.error_type,
        'component', NEW.component_name,
        'action', NEW.action_attempted
      )
    FROM public.user_roles ur
    WHERE ur.role = 'admin'::app_role;
  END IF;
  
  RETURN NEW;
END;
$$;