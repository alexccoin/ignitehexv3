-- Strengthen voucher_redemptions RLS policies for better security

-- Drop existing policies to recreate them with enhanced security
DROP POLICY IF EXISTS "Users can view their own voucher redemptions" ON public.voucher_redemptions;
DROP POLICY IF EXISTS "Admins can view all voucher redemptions" ON public.voucher_redemptions;
DROP POLICY IF EXISTS "Users can update their own pending voucher redemptions" ON public.voucher_redemptions;

-- Enhanced user access policy - users can only view their own voucher redemptions
CREATE POLICY "Users can view own voucher redemptions secure" ON public.voucher_redemptions
FOR SELECT
TO authenticated
USING (
  auth.uid() IS NOT NULL AND 
  auth.uid() = user_id
);

-- Enhanced admin access policy - only verified admins can view all voucher redemptions
CREATE POLICY "Verified admins can view all voucher redemptions secure" ON public.voucher_redemptions
FOR SELECT
TO authenticated
USING (
  auth.uid() IS NOT NULL AND 
  is_admin(auth.uid()) = true
);

-- Enhanced update policy - stricter conditions for updates
CREATE POLICY "Secure voucher update policy" ON public.voucher_redemptions
FOR UPDATE
TO authenticated
USING (
  auth.uid() IS NOT NULL AND 
  (
    (auth.uid() = user_id AND status = 'pending') OR 
    is_admin(auth.uid()) = true
  )
)
WITH CHECK (
  auth.uid() IS NOT NULL AND 
  (
    auth.uid() = user_id OR 
    is_admin(auth.uid()) = true
  )
);

-- Add audit logging function for voucher modifications (not SELECT)
CREATE OR REPLACE FUNCTION log_voucher_modifications()
RETURNS TRIGGER AS $$
BEGIN
  -- Log voucher data modifications for security monitoring
  INSERT INTO security_audit_log (
    user_id,
    action,
    resource_type,
    resource_id,
    details
  ) VALUES (
    auth.uid(),
    TG_OP || '_voucher_redemption',
    'voucher_redemptions',
    COALESCE(NEW.id, OLD.id)::text,
    jsonb_build_object(
      'operation', TG_OP,
      'table', 'voucher_redemptions',
      'contains_pii', true,
      'timestamp', now(),
      'previous_status', CASE WHEN TG_OP = 'UPDATE' THEN OLD.status ELSE null END,
      'new_status', CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN NEW.status ELSE null END
    )
  );
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Add trigger for voucher modifications only (INSERT, UPDATE, DELETE)
DROP TRIGGER IF EXISTS trigger_log_voucher_modifications ON public.voucher_redemptions;
CREATE TRIGGER trigger_log_voucher_modifications
  AFTER INSERT OR UPDATE OR DELETE ON public.voucher_redemptions
  FOR EACH ROW EXECUTE FUNCTION log_voucher_modifications();