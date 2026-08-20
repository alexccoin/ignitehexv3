-- Just add search path to existing is_admin function without changing signature
CREATE OR REPLACE FUNCTION public.is_admin(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      -- REPAIR: compared role (app_role) against _user_id (uuid), which is not
      -- a valid comparison, so this function failed to replace and the previous
      -- is_admin definition stayed live. The intended check is the admin role.
      AND role = 'admin'::app_role
  )
$function$;