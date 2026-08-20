-- Create centralized CCoin Banking Profiles table
CREATE TABLE IF NOT EXISTS public.ccoin_banking_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Mirror essential user data
  full_name TEXT NOT NULL,
  email_address TEXT NOT NULL,
  str_domain TEXT,
  str_wallet_address TEXT,
  
  -- Banking preferences
  preferred_iban_currencies TEXT[] DEFAULT ARRAY['EUR', 'CHF', 'GBP'],
  default_iban_country TEXT DEFAULT 'CH',
  card_networks_enabled TEXT[] DEFAULT ARRAY['ccoin', 'visa'],
  
  -- Banking status flags
  eur_iban_created BOOLEAN DEFAULT FALSE,
  chf_iban_created BOOLEAN DEFAULT FALSE,
  gbp_iban_created BOOLEAN DEFAULT FALSE,
  ccoin_card_created BOOLEAN DEFAULT FALSE,
  visa_card_created BOOLEAN DEFAULT FALSE,
  
  -- Banking IDs for quick reference
  eur_iban_id UUID REFERENCES public.iban_accounts(id),
  chf_iban_id UUID REFERENCES public.iban_accounts(id),
  gbp_iban_id UUID REFERENCES public.iban_accounts(id),
  ccoin_card_id UUID REFERENCES public.prepaid_cards(id),
  visa_card_id UUID REFERENCES public.prepaid_cards(id),
  
  -- Compliance and verification
  kyc_status TEXT DEFAULT 'pending',
  banking_status TEXT DEFAULT 'active',
  
  -- Metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_banking_sync TIMESTAMPTZ,
  
  UNIQUE(user_id)
);

-- Enable RLS
ALTER TABLE public.ccoin_banking_profiles ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Admins can manage all banking profiles"
ON public.ccoin_banking_profiles
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Users can view their own banking profile"
ON public.ccoin_banking_profiles
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION public.update_ccoin_banking_profiles_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE TRIGGER update_ccoin_banking_profiles_updated_at
BEFORE UPDATE ON public.ccoin_banking_profiles
FOR EACH ROW
EXECUTE FUNCTION public.update_ccoin_banking_profiles_timestamp();

-- Function to initialize banking profile from user_profiles
CREATE OR REPLACE FUNCTION public.initialize_ccoin_banking_profile(p_user_id UUID)
RETURNS UUID AS $$
DECLARE
  v_profile_id UUID;
  v_full_name TEXT;
  v_email TEXT;
  v_str_domain TEXT;
  v_str_wallet TEXT;
BEGIN
  -- Get user profile data
  SELECT 
    full_name,
    email_address,
    str_domain_owned,
    str_wallet_address
  INTO v_full_name, v_email, v_str_domain, v_str_wallet
  FROM public.user_profiles
  WHERE user_id = p_user_id;
  
  -- Create or update banking profile
  INSERT INTO public.ccoin_banking_profiles (
    user_id,
    full_name,
    email_address,
    str_domain,
    str_wallet_address
  ) VALUES (
    p_user_id,
    COALESCE(v_full_name, 'Unknown'),
    COALESCE(v_email, ''),
    v_str_domain,
    v_str_wallet
  )
  ON CONFLICT (user_id) DO UPDATE SET
    full_name = COALESCE(EXCLUDED.full_name, ccoin_banking_profiles.full_name),
    email_address = COALESCE(EXCLUDED.email_address, ccoin_banking_profiles.email_address),
    str_domain = COALESCE(EXCLUDED.str_domain, ccoin_banking_profiles.str_domain),
    str_wallet_address = COALESCE(EXCLUDED.str_wallet_address, ccoin_banking_profiles.str_wallet_address),
    updated_at = now()
  RETURNING id INTO v_profile_id;
  
  RETURN v_profile_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Function to create complete banking for a user via banking profile
CREATE OR REPLACE FUNCTION public.create_complete_banking_via_profile(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_banking_profile_id UUID;
  v_str_domain TEXT;
  v_wallet_address TEXT;
  v_eur_iban_id UUID;
  v_chf_iban_id UUID;
  v_gbp_iban_id UUID;
  v_ccoin_card_id UUID;
  v_visa_card_id UUID;
  v_result JSONB := '{}'::jsonb;
BEGIN
  -- Initialize banking profile
  v_banking_profile_id := public.initialize_ccoin_banking_profile(p_user_id);
  
  -- Get profile data
  SELECT str_domain, str_wallet_address
  INTO v_str_domain, v_wallet_address
  FROM public.ccoin_banking_profiles
  WHERE user_id = p_user_id;
  
  -- Create EUR IBAN if not exists
  IF NOT EXISTS (SELECT 1 FROM public.iban_accounts WHERE user_id = p_user_id AND currency = 'EUR') THEN
    v_eur_iban_id := public.create_iban_for_user(p_user_id, v_str_domain, 'EUR');
    UPDATE public.ccoin_banking_profiles SET eur_iban_id = v_eur_iban_id, eur_iban_created = TRUE WHERE user_id = p_user_id;
    v_result := jsonb_set(v_result, '{eur_iban}', to_jsonb(v_eur_iban_id));
  END IF;
  
  -- Create CHF IBAN if not exists
  IF NOT EXISTS (SELECT 1 FROM public.iban_accounts WHERE user_id = p_user_id AND currency = 'CHF') THEN
    v_chf_iban_id := public.create_iban_for_user(p_user_id, v_str_domain, 'CHF');
    UPDATE public.ccoin_banking_profiles SET chf_iban_id = v_chf_iban_id, chf_iban_created = TRUE WHERE user_id = p_user_id;
    v_result := jsonb_set(v_result, '{chf_iban}', to_jsonb(v_chf_iban_id));
  END IF;
  
  -- Create GBP IBAN if not exists
  IF NOT EXISTS (SELECT 1 FROM public.iban_accounts WHERE user_id = p_user_id AND currency = 'GBP') THEN
    v_gbp_iban_id := public.create_iban_for_user(p_user_id, v_str_domain, 'GBP');
    UPDATE public.ccoin_banking_profiles SET gbp_iban_id = v_gbp_iban_id, gbp_iban_created = TRUE WHERE user_id = p_user_id;
    v_result := jsonb_set(v_result, '{gbp_iban}', to_jsonb(v_gbp_iban_id));
  END IF;
  
  -- Create CCoin card if not exists
  IF NOT EXISTS (SELECT 1 FROM public.prepaid_cards WHERE user_id = p_user_id AND network = 'ccoin') THEN
    v_ccoin_card_id := public.create_ccoin_card_for_user(p_user_id, v_str_domain);
    UPDATE public.ccoin_banking_profiles SET ccoin_card_id = v_ccoin_card_id, ccoin_card_created = TRUE WHERE user_id = p_user_id;
    v_result := jsonb_set(v_result, '{ccoin_card}', to_jsonb(v_ccoin_card_id));
  END IF;
  
  -- Create Visa card if not exists
  IF NOT EXISTS (SELECT 1 FROM public.prepaid_cards WHERE user_id = p_user_id AND network = 'visa') THEN
    v_visa_card_id := public.create_visa_card_for_user(p_user_id, v_str_domain);
    UPDATE public.ccoin_banking_profiles SET visa_card_id = v_visa_card_id, visa_card_created = TRUE WHERE user_id = p_user_id;
    v_result := jsonb_set(v_result, '{visa_card}', to_jsonb(v_visa_card_id));
  END IF;
  
  -- Update last sync
  UPDATE public.ccoin_banking_profiles SET last_banking_sync = now() WHERE user_id = p_user_id;
  
  RETURN jsonb_build_object(
    'success', TRUE,
    'banking_profile_id', v_banking_profile_id,
    'created', v_result
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Backfill existing users
INSERT INTO public.ccoin_banking_profiles (user_id, full_name, email_address, str_domain, str_wallet_address)
SELECT 
  user_id,
  COALESCE(full_name, 'Unknown'),
  COALESCE(email_address, ''),
  str_domain_owned,
  str_wallet_address
FROM public.user_profiles
WHERE status = 'approved'
ON CONFLICT (user_id) DO NOTHING;