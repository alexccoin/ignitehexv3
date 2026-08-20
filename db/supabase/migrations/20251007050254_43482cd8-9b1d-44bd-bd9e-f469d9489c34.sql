-- Create comprehensive STARW interaction history table
CREATE TABLE IF NOT EXISTS public.starw_interaction_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  starw_purchase_id UUID REFERENCES public.starw_purchases(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  performed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action_type TEXT NOT NULL,
  action_description TEXT NOT NULL,
  status_from TEXT,
  status_to TEXT,
  payment_details JSONB,
  metadata JSONB DEFAULT '{}'::jsonb,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS on history
ALTER TABLE public.starw_interaction_history ENABLE ROW LEVEL SECURITY;

-- Admins can view all interaction history
CREATE POLICY "Admins can view all STARW interaction history"
  ON public.starw_interaction_history
  FOR SELECT
  USING (is_admin(auth.uid()));

-- System can insert interaction history
CREATE POLICY "System can insert STARW interaction history"
  ON public.starw_interaction_history
  FOR INSERT
  WITH CHECK (true);

-- Users can view their own interaction history
CREATE POLICY "Users can view own STARW interaction history"
  ON public.starw_interaction_history
  FOR SELECT
  USING (auth.uid() = user_id);

-- Create indexes for performance
CREATE INDEX idx_starw_history_purchase_id ON public.starw_interaction_history(starw_purchase_id);
CREATE INDEX idx_starw_history_user_id ON public.starw_interaction_history(user_id);
CREATE INDEX idx_starw_history_created_at ON public.starw_interaction_history(created_at DESC);
CREATE INDEX idx_starw_history_action_type ON public.starw_interaction_history(action_type);

-- Add more detailed columns to starw_purchases for better tracking
ALTER TABLE public.starw_purchases 
ADD COLUMN IF NOT EXISTS crypto_prices_at_purchase JSONB DEFAULT '{}'::jsonb,
ADD COLUMN IF NOT EXISTS btc_amount NUMERIC,
ADD COLUMN IF NOT EXISTS eth_amount NUMERIC,
ADD COLUMN IF NOT EXISTS payment_currency TEXT,
ADD COLUMN IF NOT EXISTS ip_address INET,
ADD COLUMN IF NOT EXISTS user_agent TEXT,
ADD COLUMN IF NOT EXISTS referral_source TEXT,
ADD COLUMN IF NOT EXISTS session_metadata JSONB DEFAULT '{}'::jsonb;

-- Create trigger to log all status changes
CREATE OR REPLACE FUNCTION log_starw_status_change()
RETURNS TRIGGER AS $$
BEGIN
  IF (TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status) THEN
    INSERT INTO public.starw_interaction_history (
      starw_purchase_id,
      user_id,
      performed_by,
      action_type,
      action_description,
      status_from,
      status_to,
      metadata
    ) VALUES (
      NEW.id,
      NEW.user_id,
      NEW.processed_by,
      'status_change',
      'Purchase status changed from ' || OLD.status || ' to ' || NEW.status,
      OLD.status,
      NEW.status,
      jsonb_build_object(
        'admin_notes', NEW.admin_notes,
        'processed_at', NEW.processed_at,
        'timestamp', now()
      )
    );
  END IF;
  
  IF (TG_OP = 'INSERT') THEN
    INSERT INTO public.starw_interaction_history (
      starw_purchase_id,
      user_id,
      performed_by,
      action_type,
      action_description,
      payment_details,
      metadata
    ) VALUES (
      NEW.id,
      NEW.user_id,
      NEW.user_id,
      'purchase_created',
      'New STARW node purchase request created: ' || NEW.node_count || ' nodes',
      NEW.payment_info,
      jsonb_build_object(
        'node_count', NEW.node_count,
        'total_cost', NEW.total_cost,
        'arss_bonus', NEW.arss_bonus,
        'stage', NEW.stage,
        'payment_method', NEW.payment_method,
        'crypto_prices', NEW.crypto_prices_at_purchase,
        'timestamp', now()
      )
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Create trigger
CREATE TRIGGER starw_purchase_history_trigger
  AFTER INSERT OR UPDATE ON public.starw_purchases
  FOR EACH ROW
  EXECUTE FUNCTION log_starw_status_change();

-- Create admin view for comprehensive reporting
CREATE OR REPLACE VIEW public.starw_purchases_comprehensive AS
SELECT 
  sp.*,
  up.full_name as processed_by_name,
  up.email_address as processed_by_email,
  user_up.str_wallet_address as customer_wallet,
  user_up.bsc_wallet_address as customer_bsc_wallet,
  (
    SELECT COUNT(*) 
    FROM starw_interaction_history 
    WHERE starw_purchase_id = sp.id
  ) as interaction_count,
  (
    SELECT json_agg(
      json_build_object(
        'action_type', action_type,
        'action_description', action_description,
        'created_at', created_at,
        'performed_by', performed_by
      ) ORDER BY created_at DESC
    )
    FROM starw_interaction_history 
    WHERE starw_purchase_id = sp.id
  ) as interaction_history
FROM public.starw_purchases sp
LEFT JOIN public.user_profiles up ON sp.processed_by = up.user_id
LEFT JOIN public.user_profiles user_up ON sp.user_id = user_up.user_id;

-- Grant access to admin view
GRANT SELECT ON public.starw_purchases_comprehensive TO authenticated;