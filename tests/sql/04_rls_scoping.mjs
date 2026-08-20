/**
 * RLS scopes a member to their own rows.
 *
 * The shape of the failure this guards against is quiet: a member's own page
 * looks completely normal while every other member's rows are also in the
 * response. Nothing on screen is wrong; the data behind it is everybody's.
 *
 * Each case therefore asserts three things, and the third is the one that
 * catches a vacuous test:
 *
 *   1. what the member gets back is exactly their own rows;
 *   2. no row belonging to anyone else appears;
 *   3. there ARE rows belonging to someone else to leak. A table with one
 *      member's data in it proves nothing about isolation, and
 *      member_support_tickets was empty on this stack until this file seeded
 *      it — a scoping test over an empty table is the most reassuring useless
 *      test there is.
 */

const FIXTURE_MARK = 'rls-scoping-fixture';

/** Every row a member can see through PostgREST, as ids. */
async function visibleIds(ctx, table, as, select = 'id,user_id') {
  const res = await ctx.api(`/rest/v1/${table}?select=${select}`, { as });
  if (res.status !== 200 || !Array.isArray(res.body)) {
    throw new ctx.Failed(
      `GET ${table} did not return a list\n            got    HTTP ${res.status} ${JSON.stringify(res.body)}`
    );
  }
  return res.body;
}

/** The three-part assertion, applied to one table. */
async function assertScoped(ctx, table, { select = 'id,user_id', ownerColumn = 'user_id' } = {}) {
  const mine = ctx.scalar(
    `SELECT count(*)::text FROM public.${table} WHERE ${ownerColumn} = '${ctx.as.member.userId}';`
  );
  const theirs = ctx.scalar(
    `SELECT count(*)::text FROM public.${table} WHERE ${ownerColumn} <> '${ctx.as.member.userId}';`
  );

  // (3) first: if there is nothing to leak, the rest of this proves nothing.
  ctx.expect.ok(
    Number(theirs) > 0,
    `${table} holds no rows belonging to anyone else, so this test cannot detect a leak`,
    { mine, theirs }
  );

  const rows = await visibleIds(ctx, table, ctx.as.member, select);

  // (2) nothing belonging to anyone else.
  const foreign = rows.filter((r) => r[ownerColumn] !== ctx.as.member.userId);
  ctx.expect.ok(
    foreign.length === 0,
    `${table} leaked ${foreign.length} row(s) belonging to other members`,
    foreign.slice(0, 3)
  );

  // (1) exactly their own.
  ctx.expect.equal(
    String(rows.length),
    String(mine),
    `${table}: the member sees a different number of rows than they own`
  );
}

export default {
  name: 'RLS scopes a member to their own rows',

  setup(ctx) {
    ctx.me = ctx.as.member.userId;
    ctx.them = ctx.as.other.userId;

    // member_support_tickets is empty on a freshly seeded stack. Seed one
    // ticket for the member and one for somebody else, so the test has both a
    // row to find and a row it must not find.
    ctx.sql(`
      DELETE FROM public.member_support_tickets WHERE error_details = '${FIXTURE_MARK}';
      INSERT INTO public.member_support_tickets
        (user_id, user_email, category, error_details, severity, status)
      VALUES
        ('${ctx.me}',   'newbie@ignitehex.local',    'banking', '${FIXTURE_MARK}', 'low', 'pending'),
        ('${ctx.them}', 'investor1@ignitehex.local', 'staking', '${FIXTURE_MARK}', 'low', 'pending');
    `);
  },

  teardown(ctx) {
    ctx.sql(`DELETE FROM public.member_support_tickets WHERE error_details = '${FIXTURE_MARK}';`);
  },

  cases: [
    {
      name: 'user_staking_pools: a member sees only their own pools',
      run: (ctx) => assertScoped(ctx, 'user_staking_pools'),
    },
    {
      name: 'v2_accounts: a member sees only their own account',
      run: (ctx) => assertScoped(ctx, 'v2_accounts'),
    },
    {
      name: 'member_support_tickets: a member sees only their own tickets',
      run: (ctx) => assertScoped(ctx, 'member_support_tickets'),
    },

    /* ------------------------------------------- filtering does not help */
    {
      name: 'asking for someone else\'s rows by user_id returns nothing',
      async run(ctx) {
        // RLS is applied after the filter, so a targeted request is refused the
        // same way a broad one is. Worth its own case because "I only see mine
        // in the list view" is the reassurance that hides a leak here.
        for (const table of ['user_staking_pools', 'v2_accounts', 'member_support_tickets']) {
          const res = await ctx.api(`/rest/v1/${table}?user_id=eq.${ctx.them}&select=id`, {
            as: ctx.as.member,
          });
          ctx.expect.equal(res.status, 200, `${table}: unexpected status`);
          ctx.expect.equal(
            JSON.stringify(res.body),
            '[]',
            `${table} returned another member's rows when asked for them directly`
          );
        }
      },
    },
    {
      name: 'an ANONYMOUS caller sees nothing in any of the three',
      async run(ctx) {
        for (const table of ['user_staking_pools', 'v2_accounts', 'member_support_tickets']) {
          const res = await ctx.api(`/rest/v1/${table}?select=id`);
          const leaked = Array.isArray(res.body) && res.body.length > 0;
          ctx.expect.ok(!leaked, `${table} is readable without signing in`, {
            status: res.status,
            rows: Array.isArray(res.body) ? res.body.length : res.body,
          });
        }
      },
    },

    /* ---------------------------------------------------- the ledger too */
    {
      name: 'ledger_account: a member sees only their own accounts',
      async run(ctx) {
        // Not on the original list, but it is the table that now holds the
        // authoritative balances. A leak here exposes every member's holdings.
        const theirs = ctx.scalar(
          `SELECT count(*)::text FROM public.ledger_account WHERE user_id <> '${ctx.me}';`
        );
        ctx.expect.ok(Number(theirs) > 0, 'no foreign ledger_account rows exist to leak', theirs);

        const res = await ctx.api('/rest/v1/ledger_account?select=id,user_id', { as: ctx.as.member });
        const rows = Array.isArray(res.body) ? res.body : [];
        const foreign = rows.filter((r) => r.user_id !== ctx.me);
        ctx.expect.ok(foreign.length === 0, 'ledger_account leaked other members\' balances', foreign.slice(0, 3));
      },
    },
    {
      name: 'ledger_journal is admin-only: a member sees no journal at all',
      async run(ctx) {
        const journals = ctx.scalar(`SELECT count(*)::text FROM public.ledger_journal;`);
        ctx.expect.ok(Number(journals) > 0, 'no journals exist, so this proves nothing', journals);

        const res = await ctx.api('/rest/v1/ledger_journal?select=id', { as: ctx.as.member });
        const rows = Array.isArray(res.body) ? res.body : [];
        ctx.expect.equal(
          String(rows.length),
          '0',
          'a member can read the ledger journal — every posting on the platform'
        );
      },
    },

    /* -------------------------------------------------- the mirror tests */
    {
      name: 'a member DOES see their own rows — scoping is not "return nothing"',
      async run(ctx) {
        // An RLS policy of `USING (false)` passes every leak test above and
        // leaves the member staring at an empty wallet.
        const rows = await visibleIds(ctx, 'user_staking_pools', ctx.as.member);
        ctx.expect.ok(rows.length > 0, 'a member sees none of their own staking pools', rows.length);

        const tickets = await visibleIds(ctx, 'member_support_tickets', ctx.as.member);
        ctx.expect.ok(tickets.length > 0, 'a member sees none of their own support tickets', tickets.length);
      },
    },
    {
      name: 'an ADMIN sees every member\'s rows',
      async run(ctx) {
        // The other half of the same policy. If the admin console cannot see
        // the platform, support cannot answer anyone.
        const total = Number(ctx.scalar(`SELECT count(*)::text FROM public.user_staking_pools;`));
        const rows = await visibleIds(ctx, 'user_staking_pools', ctx.as.admin, 'id,user_id');
        ctx.expect.equal(
          String(rows.length),
          String(total),
          'an admin cannot see every staking pool'
        );
        ctx.expect.ok(
          new Set(rows.map((r) => r.user_id)).size > 1,
          'the admin view contains only one member\'s pools'
        );
      },
    },
  ],
};
