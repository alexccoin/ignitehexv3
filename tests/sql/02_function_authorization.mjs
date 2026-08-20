/**
 * Who may call the money-moving functions.
 *
 * Every call here is made over PostgREST on :55321 with a real member JWT
 * obtained from `/auth/v1/token`. That is the whole point: `post_entries` and
 * friends are SECURITY DEFINER, and inside one of those `current_user` is the
 * owner, so a psql session is indistinguishable from a trusted caller. The only
 * thing that separates a browser from the service key is the verified JWT role,
 * and the only way to test it is to hold one.
 *
 * The three functions under test are the ones the audit named:
 *
 *   post_entries                 the ledger primitive. Anything that can call
 *                                it can move any balance to any other.
 *   distribute_enhanced_rewards  inserts a stake with no balance check and no
 *                                debit. This is the mint path (F-002).
 *   process_staking_request      two overloads, and they are not equally
 *                                guarded — which is exactly why both are here.
 *
 * Each denial is checked twice: the call is refused, AND nothing moved. A
 * function that raises after it has already written is not denied, it is
 * merely noisy.
 */

const bogusUuid = '00000000-0000-0000-0000-000000000000';

/** Everything about the member that a mint would change. */
function memberSnapshot(ctx) {
  const id = ctx.as.member.userId;
  const [row] = ctx.sql(
    `SELECT
       (SELECT count(*) FROM public.user_staking_pools WHERE user_id = '${id}'),
       (SELECT coalesce(sum(balance), 0) FROM public.user_staking_pools WHERE user_id = '${id}'),
       (SELECT coalesce(sum(staked_amount), 0) FROM public.user_staking_pools WHERE user_id = '${id}'),
       (SELECT coalesce(sum(rewards_earned), 0) FROM public.user_staking_pools WHERE user_id = '${id}'),
       (SELECT count(*) FROM public.ledger_journal),
       (SELECT count(*) FROM public.ledger_entry);`,
    { rows: true }
  );
  return { pools: row[0], balance: row[1], staked: row[2], rewards: row[3], journals: row[4], entries: row[5] };
}

const unchanged = (ctx, before, what) => {
  const after = memberSnapshot(ctx);
  for (const key of Object.keys(before)) {
    ctx.expect.equal(after[key], before[key], `${what}: ${key} changed`);
  }
};

/** A balanced two-leg batch. Valid arithmetic — so a refusal can only be about
 *  authorisation, never about the batch being malformed. */
const balancedBatch = (ctx) => [
  { user_id: ctx.as.other.userId, asset: 'STR', bucket: 'liquid', amount: -100 },
  { user_id: ctx.as.member.userId, asset: 'STR', bucket: 'liquid', amount: 100 },
];

export default {
  name: 'function authorisation, over a real member JWT',

  setup(ctx) {
    // A genuinely pending request the member owns, so "a member cannot approve"
    // is tested against a request that could actually be approved rather than
    // against a not-found id.
    ctx.sql(`
      DELETE FROM public.staking_requests WHERE description = 'authz-test-fixture';
      INSERT INTO public.staking_requests
        (user_id, pool_type, request_type, amount, duration_months, status, description)
      VALUES ('${ctx.as.member.userId}', 'str', 'stake', 1000, 12, 'pending', 'authz-test-fixture');
    `);
    ctx.fixtureRequestId = ctx.scalar(
      `SELECT id FROM public.staking_requests WHERE description = 'authz-test-fixture';`
    );
  },

  teardown(ctx) {
    ctx.sql(`DELETE FROM public.staking_requests WHERE description = 'authz-test-fixture';`);
  },

  cases: [
    /* ---------------------------------------------------------- grants */
    {
      name: 'the catalogue agrees: authenticated and anon hold no EXECUTE on the three functions',
      run(ctx) {
        const rows = ctx.sql(
          `SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
                  has_function_privilege('authenticated', p.oid, 'EXECUTE')::text,
                  has_function_privilege('anon', p.oid, 'EXECUTE')::text
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public'
              AND p.proname IN ('post_entries', 'distribute_enhanced_rewards')
            ORDER BY 1;`,
          { rows: true }
        );
        ctx.expect.ok(rows.length >= 2, 'expected post_entries and distribute_enhanced_rewards to exist', rows);
        for (const [name, authenticated, anon] of rows) {
          ctx.expect.equal(authenticated, 'false', `authenticated holds EXECUTE on ${name}`);
          ctx.expect.equal(anon, 'false', `anon holds EXECUTE on ${name}`);
        }
      },
    },

    /* ----------------------------------------------------- post_entries */
    {
      name: 'a member cannot execute post_entries',
      async run(ctx) {
        const before = memberSnapshot(ctx);
        const res = await ctx.rpc(
          'post_entries',
          {
            p_entries: balancedBatch(ctx),
            p_reference: `authz-member-${Date.now()}`,
            p_reason: 'a member should not be able to post to the ledger',
          },
          { as: ctx.as.member }
        );
        ctx.expect.permissionDenied(res, 'a member was able to call post_entries');
        unchanged(ctx, before, 'post_entries as member');
      },
    },
    {
      name: 'an ANONYMOUS caller cannot execute post_entries',
      async run(ctx) {
        const before = memberSnapshot(ctx);
        const res = await ctx.rpc('post_entries', {
          p_entries: balancedBatch(ctx),
          p_reference: `authz-anon-${Date.now()}`,
          p_reason: 'anon should not be able to post to the ledger',
        });
        ctx.expect.denied(res, 'an anonymous caller was able to call post_entries');
        unchanged(ctx, before, 'post_entries as anon');
      },
    },
    {
      name: 'an ADMIN cannot execute post_entries either — it is a service-role primitive',
      async run(ctx) {
        // Admin is a role in the application, not a database service identity.
        // If an admin session could post arbitrary legs, a stolen admin token
        // would be a mint. Admin operations go through wrappers that assert
        // what they are doing; the primitive stays closed.
        const before = memberSnapshot(ctx);
        const res = await ctx.rpc(
          'post_entries',
          {
            p_entries: balancedBatch(ctx),
            p_reference: `authz-admin-${Date.now()}`,
            p_reason: 'an admin should not be able to post raw legs',
          },
          { as: ctx.as.admin }
        );
        ctx.expect.permissionDenied(res, 'an admin was able to call post_entries directly');
        unchanged(ctx, before, 'post_entries as admin');
      },
    },
    {
      name: 'post_entries has a second lock in its body, not only the EXECUTE grant',
      run(ctx) {
        // The grant is the primary control, but rebuild-local.mjs has swept
        // revoked functions back open before now (F-001). A re-granted
        // post_entries is the worst thing on this list to hand a browser, so
        // the body checks the JWT role as well. This asserts the belt exists
        // as well as the braces.
        // The predicate runs in SQL rather than pulling prosrc back: a function
        // body is hundreds of lines, and the harness's scalar() reads one line.
        const [checksJwt, raises42501] = ctx.sql(
          `SELECT (prosrc LIKE '%request.jwt.claim%' AND prosrc LIKE '%service_role%')::text,
                  (prosrc LIKE '%42501%')::text
             FROM pg_proc WHERE proname = 'post_entries';`,
          { rows: true }
        )[0];
        ctx.expect.equal(
          checksJwt,
          'true',
          'post_entries no longer checks the caller JWT role in its body; the EXECUTE grant is now the only control'
        );
        ctx.expect.equal(
          raises42501,
          'true',
          'post_entries no longer raises 42501 for a non-service caller'
        );
      },
    },

    /* ------------------------------------------ distribute_enhanced_rewards */
    {
      name: 'a member cannot execute distribute_enhanced_rewards (the mint path)',
      async run(ctx) {
        const before = memberSnapshot(ctx);
        const res = await ctx.rpc(
          'distribute_enhanced_rewards',
          {
            user_id_param: ctx.as.member.userId,
            token_type_param: 'str',
            amount: 1_000_000,
            duration_months_param: 12,
            network_efficiency_param: 1,
          },
          { as: ctx.as.member }
        );
        ctx.expect.permissionDenied(
          res,
          'a member was able to call distribute_enhanced_rewards — this inserts a stake with no balance check and no debit'
        );
        unchanged(ctx, before, 'distribute_enhanced_rewards as member');
      },
    },
    {
      name: 'an anonymous caller cannot execute distribute_enhanced_rewards',
      async run(ctx) {
        const before = memberSnapshot(ctx);
        const res = await ctx.rpc('distribute_enhanced_rewards', {
          user_id_param: ctx.as.member.userId,
          token_type_param: 'str',
          amount: 1_000_000,
          duration_months_param: 12,
          network_efficiency_param: 1,
        });
        ctx.expect.denied(res, 'an anonymous caller reached distribute_enhanced_rewards');
        unchanged(ctx, before, 'distribute_enhanced_rewards as anon');
      },
    },
    {
      name: 'a member cannot mint to SOMEONE ELSE through distribute_enhanced_rewards',
      async run(ctx) {
        // The function takes the beneficiary as a parameter, so "it only
        // affects me" is not a mitigation.
        const res = await ctx.rpc(
          'distribute_enhanced_rewards',
          {
            user_id_param: ctx.as.other.userId,
            token_type_param: 'str',
            amount: 1_000_000,
            duration_months_param: 12,
            network_efficiency_param: 1,
          },
          { as: ctx.as.member }
        );
        ctx.expect.permissionDenied(res, 'a member minted into another account');
      },
    },

    /* --------------------------------------- process_staking_request, both */
    {
      name: 'a member cannot execute process_staking_request(p_request_id, p_action, p_admin_notes)',
      async run(ctx) {
        const res = await ctx.rpc(
          'process_staking_request',
          {
            p_request_id: ctx.fixtureRequestId,
            p_action: 'approve',
            p_admin_notes: 'a member approving their own request',
          },
          { as: ctx.as.member }
        );
        ctx.expect.permissionDenied(res, 'a member reached the p_request_id overload');
      },
    },
    {
      name: 'a member cannot approve their own staking request through the other overload',
      async run(ctx) {
        // This overload IS executable by `authenticated` — the grant was never
        // revoked — so the only thing standing in the way is the in-body
        // is_admin() check. That makes this the sharper of the two tests.
        const res = await ctx.rpc(
          'process_staking_request',
          {
            request_id: ctx.fixtureRequestId,
            approve: true,
            admin_notes_param: 'a member approving their own request',
          },
          { as: ctx.as.member }
        );

        // The request must still be pending. This is the assertion that matters:
        // whatever the function answers, it must not have approved anything.
        const status = ctx.scalar(
          `SELECT status FROM public.staking_requests WHERE id = '${ctx.fixtureRequestId}';`
        );
        ctx.expect.equal(status, 'pending', 'a member APPROVED their own staking request');

        // And it must not report success.
        const succeeded = res.status < 300 && res.body?.success === true;
        ctx.expect.ok(
          !succeeded,
          'process_staking_request reported success to a member',
          { status: res.status, body: res.body }
        );
      },
    },
    {
      name: 'that overload refuses a member for the RIGHT reason, and says so',
      run(ctx) {
        // Guarding by returning "not found" would be indistinguishable from a
        // stale id and would hide the authorisation failure from the logs.
        const [callsIsAdmin, adminAt, lookupAt] = ctx.sql(
          `SELECT (prosrc LIKE '%is_admin(%')::text,
                  position('is_admin(' in prosrc)::text,
                  position('FROM staking_requests' in prosrc)::text
             FROM pg_proc p
            WHERE p.proname = 'process_staking_request'
              AND pg_get_function_identity_arguments(p.oid) LIKE 'request_id%';`,
          { rows: true }
        )[0];

        ctx.expect.equal(
          callsIsAdmin,
          'true',
          'the authenticated-executable process_staking_request overload no longer calls is_admin'
        );
        // The admin check must come before the request is read, or a member
        // learns whether an id exists from the shape of the refusal.
        ctx.expect.ok(
          Number(adminAt) > 0 && (Number(lookupAt) === 0 || Number(adminAt) < Number(lookupAt)),
          'the is_admin check no longer precedes the staking_requests lookup',
          { adminAt, lookupAt }
        );
      },
    },
    {
      name: 'an admin CAN reach the guarded overload — the lock is not just "deny everyone"',
      async run(ctx) {
        // The mirror test. A function that refuses everybody passes every
        // denial test above and breaks the platform.
        const res = await ctx.rpc(
          'process_staking_request',
          { request_id: bogusUuid, approve: false, admin_notes_param: 'reachability probe' },
          { as: ctx.as.admin }
        );
        ctx.expect.ok(
          res.status < 300,
          'an admin could not reach process_staking_request at all',
          { status: res.status, body: res.body }
        );
        ctx.expect.ok(
          res.body?.error !== 'Admin privileges required',
          'an admin was told they lack admin privileges',
          res.body
        );
      },
    },

    /* ------------------------------------------------- what a member MAY do */
    {
      name: 'a member CAN read their own available balance — the suite is not just "everything is denied"',
      async run(ctx) {
        const res = await ctx.rpc(
          'get_available_balance',
          { p_user_id: ctx.as.member.userId, p_token_type: 'str' },
          { as: ctx.as.member }
        );
        ctx.expect.ok(
          res.status === 200,
          'a member could not read their own available balance',
          { status: res.status, body: res.body }
        );
        ctx.expect.ok(
          res.body !== null && Number.isFinite(Number(res.body)),
          'get_available_balance did not return a number',
          res.body
        );
      },
    },
  ],
};
