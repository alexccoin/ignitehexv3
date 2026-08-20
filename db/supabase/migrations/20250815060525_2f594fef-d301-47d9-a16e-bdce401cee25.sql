-- Fix RLS policies for currency exchanges to allow user inserts
DROP POLICY IF EXISTS "Users can insert their own currency exchanges" ON public.currency_exchanges;
CREATE POLICY "Users can insert their own currency exchanges" 
ON public.currency_exchanges 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Fix RLS policies for cross-border payments to allow user inserts  
DROP POLICY IF EXISTS "Users can insert their own cross-border payments" ON public.cross_border_payments;
CREATE POLICY "Users can insert their own cross-border payments" 
ON public.cross_border_payments 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Fix RLS policies for prepaid cards to allow user inserts
DROP POLICY IF EXISTS "Users can insert their own prepaid cards" ON public.prepaid_cards;
CREATE POLICY "Users can insert their own prepaid cards" 
ON public.prepaid_cards 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Fix user_messages policies to allow proper insert access
DROP POLICY IF EXISTS "Users can insert their own messages" ON public.user_messages;
CREATE POLICY "Users can insert their own messages" 
ON public.user_messages 
FOR INSERT 
WITH CHECK (auth.uid() = sender_id);