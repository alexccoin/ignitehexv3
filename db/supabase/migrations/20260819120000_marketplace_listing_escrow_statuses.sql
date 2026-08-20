-- F-006: token_marketplace_listings_status_check rejects the two statuses the
-- escrow sell path writes.
--
-- WHAT WAS OBSERVED
--
-- The constraint, identically in production (lhkkfrpgbkjfcrodjslf) and on the
-- self-hosted stack:
--
--   CHECK (status = ANY (ARRAY['active','sold','cancelled','expired','reserved']))
--
-- v3 writes 'pending_escrow' at src/domains/marketplace/hooks.ts:672 and
-- 'escrow_error' at :722. Neither is permitted, so the INSERT that opens the
-- sell path fails with 23514 before anything else in the flow runs. The gap is
-- NOT local drift: production carries the same five-value constraint, so the
-- token sell path is broken there too.
--
-- WHY THE CONSTRAINT MOVES AND NOT THE APP
--
-- The ordering in hooks.ts is the safety property. The listing is inserted
-- invisible, THEN the balance is debited, THEN the escrow row is written, and
-- only then is the listing published. A debit that fails therefore leaves a row
-- nobody can buy, rather than a purchasable advert backed by tokens that were
-- never locked. Making the app write an already-modelled status would break
-- that:
--
--   * 'active' first inverts the ordering outright - the listing would be
--     purchasable before the tokens were locked. This is the failure the flow
--     exists to prevent.
--   * 'reserved' already means "a buyer has claimed this pending settlement"
--     in the domain flow (hooks.ts:784) and is read with that meaning by
--     marketplace_escrow_release. Overloading it would make "seller's tokens
--     are not yet locked" and "a buyer is mid-purchase" the same value.
--   * 'cancelled' is what marketplace_escrow_release writes when it unwinds a
--     listing, so a draft would be indistinguishable from a released one.
--   * No existing value means "debited but the escrow record did not save".
--     That state is real, it is the one a support agent has to act on, and
--     collapsing it into 'cancelled' would erase the only marker that tokens
--     are stranded.
--
-- The invisibility of a draft does not depend on the status being unmodelled.
-- It is enforced twice, independently of this constraint:
--
--   * RLS: "Authenticated users can view active token listings"
--     USING (status = 'active' OR seller_id = auth.uid())
--   * every read filters .eq('status','active') (hooks.ts:309, :499)
--
-- so any value that is not 'active' is invisible to a buyer. Widening the
-- constraint adds two states; it does not add any way to see them.
--
-- Finally, the server side already assumes these two states exist:
-- marketplace_escrow_release (20260818160000_ledger_post_entries.sql:1016)
-- transitions status IN ('active','pending_escrow','escrow_error','reserved').
-- The constraint is the outlier here, not the application.
--
-- No v3 frontend code is changed by this migration.

BEGIN;

ALTER TABLE public.token_marketplace_listings
  DROP CONSTRAINT IF EXISTS token_marketplace_listings_status_check;

ALTER TABLE public.token_marketplace_listings
  ADD CONSTRAINT token_marketplace_listings_status_check
  CHECK (status = ANY (ARRAY[
    -- The five that were already permitted, unchanged.
    'active'::text,
    'sold'::text,
    'cancelled'::text,
    'expired'::text,
    'reserved'::text,
    -- Inserted before the debit. Invisible to buyers by RLS. Deleted by the
    -- client if the debit is refused, and promoted to 'active' if it succeeds.
    -- NOTE, and it cost a rebuild to find: there must be no semicolon anywhere
    -- inside this statement, these comments included.
    -- scripts/repair-migrations.mjs:224 rewrites ADD CONSTRAINT into a guarded
    -- DO block, and the regex it uses to find the end of the statement stops
    -- at the first semicolon whether or not that semicolon is inside a
    -- comment. One here splits the DO block in half and the replay dies with
    -- "unexpected end of function definition at end of input". See F-029.
    'pending_escrow'::text,
    -- Terminal-until-a-human-looks. The debit succeeded and the escrow row did
    -- not, so tokens are held with no record of what holds them. Deliberately
    -- distinct from 'cancelled': this one needs a server-side credit to unwind.
    'escrow_error'::text
  ]));

COMMENT ON CONSTRAINT token_marketplace_listings_status_check
  ON public.token_marketplace_listings IS
  'pending_escrow and escrow_error are the escrow sell path''s pre-publication states. Neither is visible to a buyer: the SELECT policy admits status = ''active'' or the seller''s own rows only.';

-- ---------------------------------------------------------------------------
-- The second half of F-006, found by running the flow rather than reading it.
-- ---------------------------------------------------------------------------
-- With the constraint widened, steps 1-4 of the happy path all succeed. The
-- FAILED-debit branch still does not: hooks.ts:686-696 deletes the draft when
-- the debit is refused, and token_marketplace_listings had SELECT, INSERT and
-- UPDATE policies and no DELETE policy at all. RLS denies an uncovered command
-- silently, so the DELETE returned HTTP 200 with zero rows affected, and
-- affectedRows(cleanup.data) === 0 sent the member the worst message in the
-- file - "the draft listing could not be removed and is still held as
-- pending_escrow" - on the one path where in fact nothing had gone wrong.
--
-- Production has the same three policies and no DELETE policy either, so this
-- is not local drift.
--
-- The policy is deliberately narrower than "own rows". A seller may erase a
-- draft that was never published and never backed by anything; anything that
-- has been active, sold, reserved or held in escrow_error is a record, and a
-- record is cancelled by UPDATE, not deleted. marketplace_escrow_balances also
-- carries an FK to this table, so a draft that did acquire an escrow row is
-- refused by the FK as well - two independent reasons a debited listing cannot
-- vanish.
DROP POLICY IF EXISTS "Sellers can delete their own unpublished drafts"
  ON public.token_marketplace_listings;

CREATE POLICY "Sellers can delete their own unpublished drafts"
  ON public.token_marketplace_listings
  FOR DELETE
  TO authenticated
  USING (seller_id = auth.uid() AND status = 'pending_escrow');

COMMIT;
