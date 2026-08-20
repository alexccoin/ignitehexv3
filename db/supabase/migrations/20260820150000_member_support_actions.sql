-- Member-side support actions.
--
-- The member could open a ticket and read the thread on it, but had no way to
-- reply to support or to close the ticket once their problem was solved. Both
-- gaps existed for the same reason: the only writes available were ones where
-- the browser would have had to choose a column it must not choose.
--
--   * Replying meant INSERTing into v2_request_messages with the client
--     picking `user_id` and `sender_role`. The member INSERT policy on that
--     table pins user_id and sender_id to auth.uid() and sender_role to
--     'member', so a member cannot post *as* staff -- but it says nothing
--     about `request_id`, so a member could attach a message to any request in
--     the platform, where an administrator reading that thread would see it
--     beside the real owner's messages. The policy protects the sender's
--     identity and not the thread's.
--   * Closing meant UPDATE on member_support_tickets, which grants UPDATE to
--     administrators only. A member's UPDATE is not rejected -- it is filtered
--     to zero rows and returns 204 with no error, so the UI reports success and
--     nothing changed (finding F-055).
--
-- Both are fixed the same way the admin side was: one SECURITY DEFINER routine
-- per action that re-derives the caller from auth.uid(), refuses a row the
-- caller does not own with 42501, and stamps every trust-bearing column itself.
-- These are siblings of v2_admin_message_request / v2_admin_update_request and
-- follow the same conventions: plpgsql, SET search_path = public, jsonb return,
-- REVOKE before GRANT.
--
-- Note on public.assert_caller_owns: it is deliberately NOT used here. It
-- returns successfully when auth.uid() IS NULL (server-side context) and when
-- the caller holds the admin role. Neither concession is wanted on a member
-- routine -- the first would make a token-less call succeed, and the second
-- would let an administrator post a message labelled 'member' into another
-- person's thread. The ownership test below is strict equality.

-- ---------------------------------------------------------------- reply ---

CREATE OR REPLACE FUNCTION public.v2_member_message_request(
  p_source text,
  p_id uuid,
  p_body text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_actor uuid := auth.uid();
  v_table text;
  v_user_col text := 'user_id';
  v_owner uuid;
  v_msg public.v2_request_messages;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Sign in to reply to a request'
      USING ERRCODE = '42501';
  END IF;

  IF p_id IS NULL THEN
    RAISE EXCEPTION 'Request id required' USING ERRCODE = '22004';
  END IF;

  IF p_body IS NULL OR length(trim(p_body)) = 0 THEN
    RAISE EXCEPTION 'Message body required' USING ERRCODE = '22004';
  END IF;

  -- The admin routine has no length bound because staff are trusted; this one
  -- is reachable by any signed-in member, and body is unbounded text.
  IF length(trim(p_body)) > 5000 THEN
    RAISE EXCEPTION 'Message is too long (limit 5000 characters)'
      USING ERRCODE = '22001';
  END IF;

  -- Same source vocabulary as v2_admin_update_request, so a member can answer
  -- an information request on any of their own queue items, not only tickets.
  CASE p_source
    WHEN 'member_support_tickets'   THEN v_table := 'member_support_tickets';
    WHEN 'arx_support_tickets'      THEN v_table := 'arx_support_tickets'; v_user_col := 'submitted_by';
    WHEN 'missing_asset_reports'    THEN v_table := 'missing_asset_reports';
    WHEN 'pending_profile_changes'  THEN v_table := 'pending_profile_changes';
    WHEN 'user_profiles_updated'    THEN v_table := 'user_profiles_updated';
    WHEN 'staking_requests'         THEN v_table := 'staking_requests';
    WHEN 'str_dome_requests'        THEN v_table := 'str_dome_requests';
    WHEN 'withdrawal_requests'      THEN v_table := 'withdrawal_requests';
    WHEN 'ipo_listing_requests'     THEN v_table := 'ipo_listing_requests';
    WHEN 'voucher_redemptions'      THEN v_table := 'voucher_redemptions';
    ELSE
      RAISE EXCEPTION 'Unsupported request source: %', p_source;
  END CASE;

  EXECUTE format('SELECT t.%I FROM public.%I t WHERE t.id = $1', v_user_col, v_table)
    INTO v_owner USING p_id;

  -- Missing row and someone else's row are answered identically, so that this
  -- function cannot be used to test whether a given uuid exists.
  IF v_owner IS NULL OR v_owner <> v_actor THEN
    RAISE EXCEPTION 'This request does not belong to you'
      USING ERRCODE = '42501';
  END IF;

  -- Every column that decides who this message is from is written here, from
  -- the session. Nothing the caller sent reaches sender_role or user_id.
  INSERT INTO public.v2_request_messages (
    source, request_id, user_id, sender_role, sender_id, body, requires_response
  )
  VALUES (
    p_source, p_id, v_actor, 'member', v_actor, trim(p_body), false
  )
  RETURNING * INTO v_msg;

  -- Narrow return: the row also carries user_id and sender_id, and the member
  -- screens are built on never handling an identity column at all.
  RETURN jsonb_build_object(
    'id', v_msg.id,
    'source', v_msg.source,
    'request_id', v_msg.request_id,
    'sender_role', v_msg.sender_role,
    'body', v_msg.body,
    'requires_response', v_msg.requires_response,
    'created_at', v_msg.created_at
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.v2_member_message_request(text, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.v2_member_message_request(text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.v2_member_message_request(text, uuid, text) TO service_role;

COMMENT ON FUNCTION public.v2_member_message_request(text, uuid, text) IS
  'Member reply on their own request. Resolves the member from auth.uid(), refuses a row they do not own with 42501, stamps sender_role itself.';

-- ---------------------------------------------------------------- close ---

CREATE OR REPLACE FUNCTION public.v2_member_close_ticket(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_actor uuid := auth.uid();
  v_owner uuid;
  v_status text;
  v_row public.member_support_tickets;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Sign in to close a ticket'
      USING ERRCODE = '42501';
  END IF;

  IF p_id IS NULL THEN
    RAISE EXCEPTION 'Ticket id required' USING ERRCODE = '22004';
  END IF;

  SELECT t.user_id, t.status INTO v_owner, v_status
  FROM public.member_support_tickets t
  WHERE t.id = p_id;

  IF v_owner IS NULL OR v_owner <> v_actor THEN
    RAISE EXCEPTION 'This ticket does not belong to you'
      USING ERRCODE = '42501';
  END IF;

  -- Idempotent: closing a closed ticket is a no-op that reports what happened
  -- rather than an error, so a double submit does not surface as a failure.
  IF lower(v_status) = 'closed' THEN
    RETURN jsonb_build_object('id', p_id, 'status', v_status, 'changed', false);
  END IF;

  -- status is the only column this statement can touch. resolved_by and
  -- resolved_at are staff attribution and are left alone -- a ticket the member
  -- closed was not resolved by anybody. updated_at is set by the table's own
  -- BEFORE UPDATE trigger.
  UPDATE public.member_support_tickets t
  SET status = 'closed'
  WHERE t.id = p_id AND t.user_id = v_actor
  RETURNING t.* INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'The ticket was not closed'
      USING ERRCODE = 'P0002';
  END IF;

  -- Narrow return for the same reason as above: the row carries admin_notes,
  -- which is the note staff write for each other.
  RETURN jsonb_build_object(
    'id', v_row.id,
    'status', v_row.status,
    'updated_at', v_row.updated_at,
    'changed', true
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.v2_member_close_ticket(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.v2_member_close_ticket(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.v2_member_close_ticket(uuid) TO service_role;

COMMENT ON FUNCTION public.v2_member_close_ticket(uuid) IS
  'Member closes their own support ticket. Scoped to auth.uid(); sets status and nothing else.';

-- ------------------------------------------------- close the INSERT hole ---
--
-- CONFIRMED by probe against the test project before this statement was added:
-- investor1 POSTed straight to /rest/v1/v2_request_messages with
-- request_id = staker1's ticket, user_id = their own, sender_role = 'member'
-- and got HTTP 201 with the row back. The policy pins *who the sender is* and
-- never checks *whose thread it is*, so any signed-in member could drop a
-- message into any request's thread, where an administrator working the queue
-- would read it beside the real owner's messages.
--
-- The policy is dropped rather than rewritten. Rewriting it would mean a
-- ten-table ownership lookup inside a WITH CHECK, evaluated on every insert and
-- duplicating the CASE in v2_member_message_request. Now that the routine
-- exists there is no reason for a member to reach the table directly at all:
-- the routine is SECURITY DEFINER and so is unaffected by RLS. Administrators
-- keep their FOR ALL policy and write through v2_admin_message_request, which
-- is likewise SECURITY DEFINER.
--
-- Checked before dropping: the only direct writer of this table anywhere in
-- either repository is none -- ignitehex-v2's AdminV2Requests.tsx reads the
-- table and sends through the RPC, and ignitehex-v3 reads it in two hooks and
-- writes it nowhere.
DROP POLICY IF EXISTS "Members reply on their request messages" ON public.v2_request_messages;

-- Table-level INSERT stays granted to authenticated because the admin FOR ALL
-- policy needs it; with no member INSERT policy, a member's direct insert is
-- now refused by RLS rather than accepted.
