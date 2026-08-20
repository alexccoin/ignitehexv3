-- Drop the existing status check constraint
ALTER TABLE ccoin_card_applications DROP CONSTRAINT ccoin_card_applications_status_check;

-- Add new constraint with on_hold status included
ALTER TABLE ccoin_card_applications ADD CONSTRAINT ccoin_card_applications_status_check 
CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'on_hold'::text]));