-- Fix existing listings with str. prefix in domain_name only
UPDATE domain_marketplace_listings 
SET domain_name = REPLACE(domain_name, 'str.', '')
WHERE domain_name LIKE 'str.%';