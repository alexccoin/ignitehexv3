-- Business Invoices Table
CREATE TABLE public.business_invoices (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  merchant_id UUID NOT NULL REFERENCES public.merchant_accounts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  invoice_number TEXT NOT NULL,
  client_name TEXT NOT NULL,
  client_email TEXT,
  client_address TEXT,
  client_tax_id TEXT,
  currency TEXT NOT NULL DEFAULT 'EUR',
  subtotal NUMERIC NOT NULL DEFAULT 0,
  tax_rate NUMERIC DEFAULT 0,
  tax_amount NUMERIC DEFAULT 0,
  total_amount NUMERIC NOT NULL DEFAULT 0,
  notes TEXT,
  due_date DATE,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'sent', 'paid', 'overdue', 'cancelled')),
  paid_at TIMESTAMP WITH TIME ZONE,
  payment_method TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Invoice Line Items
CREATE TABLE public.invoice_line_items (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  invoice_id UUID NOT NULL REFERENCES public.business_invoices(id) ON DELETE CASCADE,
  description TEXT NOT NULL,
  quantity NUMERIC NOT NULL DEFAULT 1,
  unit_price NUMERIC NOT NULL,
  total_price NUMERIC NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Business Transactions (for send/receive)
CREATE TABLE public.business_transactions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  merchant_id UUID NOT NULL REFERENCES public.merchant_accounts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  transaction_type TEXT NOT NULL CHECK (transaction_type IN ('send', 'receive', 'invoice_payment', 'refund')),
  amount NUMERIC NOT NULL,
  currency TEXT NOT NULL DEFAULT 'EUR',
  recipient_name TEXT,
  recipient_iban TEXT,
  recipient_bic TEXT,
  recipient_email TEXT,
  sender_name TEXT,
  sender_iban TEXT,
  reference TEXT,
  description TEXT,
  invoice_id UUID REFERENCES public.business_invoices(id),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  processed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.business_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_transactions ENABLE ROW LEVEL SECURITY;

-- RLS Policies for business_invoices
CREATE POLICY "Users can manage their own invoices" ON public.business_invoices
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Admins can manage all invoices" ON public.business_invoices
  FOR ALL USING (is_admin(auth.uid()));

-- RLS Policies for invoice_line_items
CREATE POLICY "Users can manage line items of their invoices" ON public.invoice_line_items
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.business_invoices 
      WHERE business_invoices.id = invoice_line_items.invoice_id 
      AND business_invoices.user_id = auth.uid()
    )
  );

CREATE POLICY "Admins can manage all line items" ON public.invoice_line_items
  FOR ALL USING (is_admin(auth.uid()));

-- RLS Policies for business_transactions
CREATE POLICY "Users can manage their own business transactions" ON public.business_transactions
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Admins can manage all business transactions" ON public.business_transactions
  FOR ALL USING (is_admin(auth.uid()));

-- Triggers for updated_at
CREATE TRIGGER update_business_invoices_updated_at
  BEFORE UPDATE ON public.business_invoices
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_business_transactions_updated_at
  BEFORE UPDATE ON public.business_transactions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Create indexes
CREATE INDEX idx_business_invoices_merchant ON public.business_invoices(merchant_id);
CREATE INDEX idx_business_invoices_status ON public.business_invoices(status);
CREATE INDEX idx_business_transactions_merchant ON public.business_transactions(merchant_id);
CREATE INDEX idx_business_transactions_status ON public.business_transactions(status);