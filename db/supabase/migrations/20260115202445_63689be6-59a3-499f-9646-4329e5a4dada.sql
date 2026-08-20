-- Fix existing affiliate records by removing str. prefix
UPDATE public.seed_str_affiliates 
SET 
  affiliate_code = REGEXP_REPLACE(affiliate_code, '^str\.', '', 'i'),
  str_domain = REGEXP_REPLACE(str_domain, '^str\.', '', 'i')
WHERE affiliate_code LIKE 'str.%' OR str_domain LIKE 'str.%';