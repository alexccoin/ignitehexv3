-- Security Fix: Add RLS policies to starw_purchases table
-- This migration adds Row Level Security to protect sensitive purchase data

-- Enable RLS on starw_purchases table
ALTER TABLE starw_purchases ENABLE ROW LEVEL SECURITY;

-- Users can only view their own purchases
CREATE POLICY "Users can view own starw purchases"
ON starw_purchases FOR SELECT
USING (auth.uid() = user_id);

-- Users can only insert their own purchases
CREATE POLICY "Users can create own starw purchases"
ON starw_purchases FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Admins can view all purchases (uses secure has_role function)
CREATE POLICY "Admins can view all starw purchases"
ON starw_purchases FOR SELECT
USING (has_role(auth.uid(), 'admin'));

-- Admins can update purchase status (uses secure has_role function)
CREATE POLICY "Admins can update starw purchases"
ON starw_purchases FOR UPDATE
USING (has_role(auth.uid(), 'admin'))
WITH CHECK (has_role(auth.uid(), 'admin'));