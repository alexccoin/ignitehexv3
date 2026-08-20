-- Admin RPC to get all STARW nodes with user details
CREATE OR REPLACE FUNCTION public.admin_get_starw_nodes()
RETURNS TABLE (
  id uuid,
  user_id uuid,
  node_number integer,
  status text,
  worker_nodes_count integer,
  assigned_by uuid,
  assigned_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  full_name text,
  email_address text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only admins can run
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  RETURN QUERY
  SELECT 
    sn.id,
    sn.user_id,
    sn.node_number,
    sn.status,
    sn.worker_nodes_count,
    sn.assigned_by,
    sn.assigned_at,
    sn.created_at,
    sn.updated_at,
    up.full_name,
    up.email_address
  FROM public.starw_nodes sn
  LEFT JOIN public.user_profiles up ON sn.user_id = up.user_id
  ORDER BY sn.node_number;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_starw_nodes() TO authenticated;