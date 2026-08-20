
-- Fix admin_assign_starw_nodes to accept admin_user_id parameter
-- This allows edge functions with service role to specify who is performing the action
DROP FUNCTION IF EXISTS public.admin_assign_starw_nodes(uuid, integer, integer, text, integer);

CREATE OR REPLACE FUNCTION public.admin_assign_starw_nodes(
  target_user_id uuid,
  node_count integer,
  start_number integer,
  node_status text,
  worker_nodes integer,
  admin_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  i integer;
  created_count integer := 0;
  checking_user_id uuid;
BEGIN
  -- Use provided admin_user_id if available, otherwise fall back to auth.uid()
  checking_user_id := COALESCE(admin_user_id, auth.uid());
  
  -- Only admins can run
  IF NOT public.has_role(checking_user_id, 'admin'::app_role) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  IF node_count IS NULL OR node_count < 1 OR node_count > 100 THEN
    RAISE EXCEPTION 'Invalid node_count (1-100)';
  END IF;
  IF start_number IS NULL OR start_number < 1 OR start_number > 100000 THEN
    RAISE EXCEPTION 'Invalid start_number';
  END IF;
  IF worker_nodes IS NULL OR worker_nodes < 0 THEN
    worker_nodes := 0;
  END IF;

  FOR i IN 0..(node_count-1) LOOP
    INSERT INTO public.starw_nodes (
      user_id,
      node_number,
      status,
      worker_nodes_count,
      assigned_by,
      assigned_at
    ) VALUES (
      target_user_id,
      start_number + i,
      node_status::text,
      worker_nodes,
      checking_user_id,
      now()
    );
    created_count := created_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'created', created_count);
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.admin_assign_starw_nodes(uuid, integer, integer, text, integer, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_assign_starw_nodes(uuid, integer, integer, text, integer, uuid) TO service_role;
