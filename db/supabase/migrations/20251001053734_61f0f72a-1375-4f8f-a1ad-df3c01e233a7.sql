-- Drop and recreate the view without security definer concerns
DROP VIEW IF EXISTS vip_users_detailed;

-- Create a regular view that respects RLS policies
CREATE VIEW vip_users_detailed 
WITH (security_invoker = true)
AS
SELECT 
  v.id,
  v.user_id,
  v.vip_status,
  v.qualification_type,
  v.total_str_staked,
  v.total_domains_staked,
  v.qualified_at,
  v.last_checked,
  up.full_name,
  up.email_address,
  up.str_domain_username
FROM vip_users v
LEFT JOIN user_profiles up ON v.user_id = up.user_id
WHERE v.vip_status = 'active'
ORDER BY v.total_str_staked DESC, v.total_domains_staked DESC;