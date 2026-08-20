
-- Guardian Invitations (admin invites users by email or STR domain)
CREATE TABLE public.guardian_invitations (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  invited_email TEXT,
  invited_str_domain TEXT,
  invited_by UUID NOT NULL,
  accepted_by UUID,
  accepted_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'expired', 'revoked')),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '30 days'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT invitation_target CHECK (invited_email IS NOT NULL OR invited_str_domain IS NOT NULL)
);

ALTER TABLE public.guardian_invitations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage guardian invitations" ON public.guardian_invitations
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Users can view their own invitations" ON public.guardian_invitations
  FOR SELECT TO authenticated
  USING (accepted_by = auth.uid());

-- Guardian Wallets (portfolio addresses per user per asset)
CREATE TABLE public.guardian_wallets (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  asset_symbol TEXT NOT NULL,
  asset_name TEXT NOT NULL,
  network TEXT NOT NULL,
  wallet_address TEXT,
  balance NUMERIC NOT NULL DEFAULT 0,
  external_balance NUMERIC NOT NULL DEFAULT 0,
  usd_value NUMERIC NOT NULL DEFAULT 0,
  icon_color TEXT DEFAULT '#F7931A',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.guardian_wallets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own wallets" ON public.guardian_wallets
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE POLICY "Admins can manage all wallets" ON public.guardian_wallets
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- Guardian Margin Settings (admin-configurable 12.5% to 17.5%)
CREATE TABLE public.guardian_margin_settings (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  asset_symbol TEXT NOT NULL,
  margin_percent NUMERIC NOT NULL DEFAULT 15.0 CHECK (margin_percent >= 12.5 AND margin_percent <= 17.5),
  auto_sell_threshold NUMERIC,
  auto_buy_threshold NUMERIC,
  target_markets TEXT[] DEFAULT ARRAY['asian', 'australian'],
  is_active BOOLEAN NOT NULL DEFAULT true,
  set_by UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.guardian_margin_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage margin settings" ON public.guardian_margin_settings
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Guardian users can view margin settings" ON public.guardian_margin_settings
  FOR SELECT TO authenticated USING (true);

-- Guardian Withdrawal Requests (96h window)
CREATE TABLE public.guardian_withdrawal_requests (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  wallet_id UUID REFERENCES public.guardian_wallets(id),
  asset_symbol TEXT NOT NULL,
  network TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  destination_address TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'approved', 'completed', 'rejected', 'cancelled')),
  admin_notes TEXT,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  window_expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '96 hours'),
  processed_at TIMESTAMPTZ,
  processed_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.guardian_withdrawal_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own withdrawals" ON public.guardian_withdrawal_requests
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE POLICY "Users can create withdrawals" ON public.guardian_withdrawal_requests
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

CREATE POLICY "Admins can manage all withdrawals" ON public.guardian_withdrawal_requests
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- Guardian Flash Alerts (market crash alerts for admin)
CREATE TABLE public.guardian_flash_alerts (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  asset_symbol TEXT NOT NULL,
  alert_type TEXT NOT NULL CHECK (alert_type IN ('crash_warning', 'flash_sell', 'flash_buy', 'margin_breach', 'liquidity_warning')),
  severity TEXT NOT NULL DEFAULT 'medium' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  title TEXT NOT NULL,
  description TEXT,
  market_price NUMERIC,
  trigger_price NUMERIC,
  action_taken TEXT,
  acted_by UUID,
  acted_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'acknowledged', 'resolved', 'dismissed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.guardian_flash_alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage flash alerts" ON public.guardian_flash_alerts
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Guardian users can view alerts" ON public.guardian_flash_alerts
  FOR SELECT TO authenticated USING (true);

-- Guardian Transactions (history log)
CREATE TABLE public.guardian_transactions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID,
  wallet_id UUID REFERENCES public.guardian_wallets(id),
  asset_symbol TEXT NOT NULL,
  transaction_type TEXT NOT NULL CHECK (transaction_type IN ('deposit', 'withdrawal', 'flash_sell', 'flash_buy', 'transfer', 'margin_adjustment')),
  amount NUMERIC NOT NULL,
  usd_value NUMERIC,
  from_address TEXT,
  to_address TEXT,
  tx_hash TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'failed', 'cancelled')),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.guardian_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own transactions" ON public.guardian_transactions
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE POLICY "Admins can manage all transactions" ON public.guardian_transactions
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- Safeguard Wallets (cold storage / reserve wallets managed by admin)
CREATE TABLE public.guardian_safeguard_wallets (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  wallet_name TEXT NOT NULL,
  asset_symbol TEXT NOT NULL,
  network TEXT NOT NULL,
  wallet_address TEXT NOT NULL,
  balance NUMERIC NOT NULL DEFAULT 0,
  wallet_type TEXT NOT NULL DEFAULT 'cold' CHECK (wallet_type IN ('cold', 'hot', 'reserve', 'liquidity')),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.guardian_safeguard_wallets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage safeguard wallets" ON public.guardian_safeguard_wallets
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Guardian users can view safeguard wallets" ON public.guardian_safeguard_wallets
  FOR SELECT TO authenticated USING (true);
