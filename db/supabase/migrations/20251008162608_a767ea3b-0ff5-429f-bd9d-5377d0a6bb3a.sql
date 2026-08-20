-- Ensure RPC is callable by authenticated users (policy remains admin-gated inside)
GRANT EXECUTE ON FUNCTION public.admin_assign_starw_nodes(uuid, integer, integer, text, integer) TO authenticated;