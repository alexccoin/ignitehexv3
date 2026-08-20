-- Add metadata column to transactions table for comprehensive transaction details
ALTER TABLE public.transactions 
ADD COLUMN metadata JSONB;