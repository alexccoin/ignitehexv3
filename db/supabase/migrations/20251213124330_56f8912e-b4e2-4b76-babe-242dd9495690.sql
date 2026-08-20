-- Clean up stale pending applications where cards already exist
UPDATE ccoin_card_applications a
SET status = 'approved',
    processed_at = NOW(),
    admin_notes = 'Auto-approved: Card already exists'
WHERE a.status = 'pending'
AND EXISTS (
  SELECT 1 FROM prepaid_cards p 
  WHERE p.user_id = a.user_id 
  AND p.network = 'ccoin'
  AND p.full_identifier IS NOT NULL
);