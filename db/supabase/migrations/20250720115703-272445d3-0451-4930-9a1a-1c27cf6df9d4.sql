-- Create user profiles table
CREATE TABLE public.profiles (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'user',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Create policies for profiles
CREATE POLICY "Users can view their own profile" 
ON public.profiles 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own profile" 
ON public.profiles 
FOR UPDATE 
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own profile" 
ON public.profiles 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Create wallet pools table for secure storage
CREATE TABLE public.wallet_pools (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  pool_type TEXT NOT NULL, -- 'BTC', 'CCOS', 'STR'
  wallet_address TEXT NOT NULL,
  balance DECIMAL NOT NULL DEFAULT 0,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.wallet_pools ENABLE ROW LEVEL SECURITY;

-- Create policies for wallet pools
CREATE POLICY "Authenticated users can view wallet pools" 
ON public.wallet_pools 
FOR SELECT 
TO authenticated
USING (true);

CREATE POLICY "Only admin users can modify wallet pools" 
ON public.wallet_pools 
FOR ALL 
TO authenticated
USING ((SELECT role FROM public.profiles WHERE user_id = auth.uid()) = 'admin');

-- Create access control table
CREATE TABLE public.pool_access (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  granted_by UUID NOT NULL REFERENCES auth.users(id),
  granted_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  expires_at TIMESTAMP WITH TIME ZONE,
  is_active BOOLEAN NOT NULL DEFAULT true
);

-- Enable RLS
ALTER TABLE public.pool_access ENABLE ROW LEVEL SECURITY;

-- Create policies for pool access
CREATE POLICY "Users can view their own access" 
ON public.pool_access 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Admin users can manage access" 
ON public.pool_access 
FOR ALL 
TO authenticated
USING ((SELECT role FROM public.profiles WHERE user_id = auth.uid()) = 'admin');

-- Create function to update timestamps
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for automatic timestamp updates
CREATE TRIGGER update_profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_wallet_pools_updated_at
BEFORE UPDATE ON public.wallet_pools
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- Function to handle new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (user_id, email, role)
  VALUES (NEW.id, NEW.email, 'user');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for new user creation
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Insert initial wallet data (this will be moved from hardcoded values)
INSERT INTO public.wallet_pools (pool_type, wallet_address, balance, user_id) VALUES
('BTC', '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa', 2.15643, (SELECT id FROM auth.users WHERE email = 'admin@ccoin.com' LIMIT 1)),
('BTC', '1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2', 1.98765, (SELECT id FROM auth.users WHERE email = 'admin@ccoin.com' LIMIT 1)),
('BTC', '3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy', 3.42187, (SELECT id FROM auth.users WHERE email = 'admin@ccoin.com' LIMIT 1)),
('BTC', '1F1tAaz5x1HUXrCNLbtMDqcw6o5GNn4xqX', 1.67429, (SELECT id FROM auth.users WHERE email = 'admin@ccoin.com' LIMIT 1)),
('BTC', '1Lbcfr7sAHTD9CgdQo3HTMTkV8LK4ZnX71', 0.89234, (SELECT id FROM auth.users WHERE email = 'admin@ccoin.com' LIMIT 1)),
('BTC', '1CX8RM5c5V13eWbijAABTTMG7CPrVYKbz', 2.15643, (SELECT id FROM auth.users WHERE email = 'admin@ccoin.com' LIMIT 1));

-- Create function to check user pool access
CREATE OR REPLACE FUNCTION public.has_pool_access(user_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 
    FROM public.pool_access 
    WHERE user_id = user_uuid 
    AND is_active = true 
    AND (expires_at IS NULL OR expires_at > now())
  ) OR EXISTS (
    SELECT 1 
    FROM public.profiles 
    WHERE user_id = user_uuid 
    AND role = 'admin'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;