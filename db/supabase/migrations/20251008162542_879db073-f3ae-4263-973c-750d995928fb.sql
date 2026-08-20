-- Admin RPC to assign STARW nodes without hitting client RLS
CREATE OR REPLACE FUNCTION public.admin_assign_starw_nodes(
  target_user_id uuid,
  node_count integer,
  start_number integer,
  node_status text,
  worker_nodes integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  i integer;
  created_count integer := 0;
BEGIN
  -- Only admins can run
  IF NOT public.is_admin(auth.uid()) THEN
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
      auth.uid(),
      now()
    );
    created_count := created_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'created', created_count);
END;
$$;