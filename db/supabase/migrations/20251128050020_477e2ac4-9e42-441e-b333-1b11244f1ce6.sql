-- Create voucher_corrections table to track all correction history
CREATE TABLE IF NOT EXISTS voucher_corrections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  voucher_id UUID NOT NULL REFERENCES voucher_redemptions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  full_name TEXT NOT NULL,
  email_address TEXT NOT NULL,
  token_type TEXT NOT NULL,
  package_type TEXT NOT NULL,
  
  -- Correction details
  previous_amount NUMERIC NOT NULL,
  corrected_amount NUMERIC NOT NULL,
  difference NUMERIC NOT NULL,
  
  -- Correction metadata
  correction_type TEXT NOT NULL, -- 'automated', 'manual'
  correction_reason TEXT,
  corrected_by UUID NOT NULL,
  corrected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Additional context
  metadata JSONB DEFAULT '{}'::jsonb,
  
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE voucher_corrections ENABLE ROW LEVEL SECURITY;

-- Admins can view all corrections
CREATE POLICY "Admins can view all voucher corrections"
  ON voucher_corrections
  FOR SELECT
  USING (has_role(auth.uid(), 'admin'::app_role));

-- Admins can insert corrections
CREATE POLICY "Admins can create voucher corrections"
  ON voucher_corrections
  FOR INSERT
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- Create index for faster queries
CREATE INDEX idx_voucher_corrections_voucher_id ON voucher_corrections(voucher_id);
CREATE INDEX idx_voucher_corrections_user_id ON voucher_corrections(user_id);
CREATE INDEX idx_voucher_corrections_corrected_at ON voucher_corrections(corrected_at DESC);

-- Function to safely update voucher credited amount with history tracking
CREATE OR REPLACE FUNCTION correct_voucher_amount(
  p_voucher_id UUID,
  p_corrected_amount NUMERIC,
  p_correction_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_voucher RECORD;
  v_admin_id UUID;
  v_result JSONB;
BEGIN
  -- Get admin user ID
  v_admin_id := auth.uid();
  
  -- Verify admin role
  IF NOT has_role(v_admin_id, 'admin'::app_role) THEN
    RAISE EXCEPTION 'Only admins can correct voucher amounts';
  END IF;
  
  -- Get current voucher details
  SELECT * INTO v_voucher
  FROM voucher_redemptions
  WHERE id = p_voucher_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Voucher not found';
  END IF;
  
  -- Insert correction history
  INSERT INTO voucher_corrections (
    voucher_id,
    user_id,
    full_name,
    email_address,
    token_type,
    package_type,
    previous_amount,
    corrected_amount,
    difference,
    correction_type,
    correction_reason,
    corrected_by
  ) VALUES (
    p_voucher_id,
    v_voucher.user_id,
    v_voucher.full_name,
    v_voucher.email_address,
    v_voucher.token_type,
    v_voucher.package_type,
    COALESCE(v_voucher.credited_amount, 0),
    p_corrected_amount,
    p_corrected_amount - COALESCE(v_voucher.credited_amount, 0),
    'manual',
    p_correction_reason,
    v_admin_id
  );
  
  -- Update voucher
  UPDATE voucher_redemptions
  SET 
    credited_amount = p_corrected_amount,
    updated_at = NOW()
  WHERE id = p_voucher_id;
  
  -- Return result
  v_result := jsonb_build_object(
    'success', true,
    'voucher_id', p_voucher_id,
    'previous_amount', COALESCE(v_voucher.credited_amount, 0),
    'corrected_amount', p_corrected_amount,
    'difference', p_corrected_amount - COALESCE(v_voucher.credited_amount, 0)
  );
  
  RETURN v_result;
END;
$$;