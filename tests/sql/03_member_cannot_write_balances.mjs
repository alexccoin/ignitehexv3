/**
 * A member cannot rewrite their own balances.
 *
 * This regressed once already (F-018). `gen-recovered-schema.mjs` emitted a
 * blanket `recovered own select/insert/update` triple on every recovered table
 * carrying a `user_id` — 46 tables got all three — and because Postgres ORs
 * permissive policies together, that blanket UPDATE walked straight past the
 * carefully written `Users can insert their own wallet` policy beside it. The
 * generator's own comment said "These are a floor, not a replacement"; for
 * INSERT and UPDATE a permissive policy is a ceiling-remover, not a floor.
 *
 * What it bought, holding nothing but a member's own bearer token:
 *
 *     PATCH /rest/v1/user_wallets?user_id=eq.<self>   {"arss_balance":999999999}   200
 *     PATCH /rest/v1/fiat_wallets?user_id=eq.<self>   {"balance":5000000}          200
 *     PATCH /rest/v1/user_staking_pools?user_id=eq.<self> {"rewards_earned":424242} 204
 *
 * Every assertion below therefore checks the DATABASE, not the HTTP status. A
 * PostgREST PATCH that matches no rows answers 200 with an empty array, and a
 * PATCH that succeeds answers 200 with the row — the two are one character
 * apart in a test that only reads the status code, which is how a suite ends up
 * green over an open database.
 */

const AMOUNT = 999_999_999;

/** Read one column straight from Postgres, as the ground truth. */
const dbValue = (ctx, table, column, where) =>
  ctx.scalar(`SELECT ${column}::text FROM public.${table} WHERE ${where} LIMIT 1;`);

export default {
  name: 'a member cannot write their own balances (F-018 regression)',

  setup(ctx) {
    ctx.me = ctx.as.member.userId;
    ctx.them = ctx.as.other.userId;

    // Every column this file tries to raise, recorded before anything runs, so
    // teardown can prove the suite itself left nothing behind.
    ctx.baseline = {
      arss: dbValue(ctx, 'user_wallets', 'arss_balance', `user_id = '${ctx.me}'`),
      fiat: ctx.scalar(
        `SELECT coalesce(sum(balance), 0)::text FROM public.fiat_wallets WHERE user_id = '${ctx.me}';`
      ),
      rewards: ctx.scalar(
        `SELECT coalesce(sum(rewards_earned), 0)::text FROM public.user_staking_pools WHERE user_id = '${ctx.me}';`
      ),
      staked: ctx.scalar(
        `SELECT coalesce(sum(staked_amount), 0)::text FROM public.user_staking_pools WHERE user_id = '${ctx.me}';`
      ),
      pools: ctx.scalar(
        `SELECT count(*)::text FROM public.user_staking_pools WHERE user_id = '${ctx.me}';`
      ),
    };
  },

  teardown(ctx) {
    // Anything this file managed to create, whether the test noticed or not.
    ctx.sql(`
      DELETE FROM public.str_domains WHERE domain_name = 'f018probe';
      DELETE FROM public.staking_requests WHERE description = 'f018-legitimate-write';
    `);
  },

  cases: [
    {
      name: 'PATCH user_wallets.arss_balance on their OWN row does not change it',
      async run(ctx) {
        const before = ctx.baseline.arss;
        ctx.expect.ok(before !== null, 'fixture missing: the member has no user_wallets row to protect');

        const res = await ctx.api(`/rest/v1/user_wallets?user_id=eq.${ctx.me}`, {
          method: 'PATCH',
          body: { arss_balance: AMOUNT },
          as: ctx.as.member,
          prefer: 'return=representation',
        });

        const after = dbValue(ctx, 'user_wallets', 'arss_balance', `user_id = '${ctx.me}'`);
        ctx.expect.equal(
          after,
          before,
          `a member rewrote their own arss_balance (HTTP ${res.status})`
        );
        ctx.expect.denied(res, 'the PATCH was accepted');
      },
    },
    {
      name: 'PATCH fiat_wallets.balance on their own row does not change it',
      async run(ctx) {
        const res = await ctx.api(`/rest/v1/fiat_wallets?user_id=eq.${ctx.me}`, {
          method: 'PATCH',
          body: { balance: 5_000_000, available_balance: 5_000_000 },
          as: ctx.as.member,
          prefer: 'return=representation',
        });

        const after = ctx.scalar(
          `SELECT coalesce(sum(balance), 0)::text FROM public.fiat_wallets WHERE user_id = '${ctx.me}';`
        );
        ctx.expect.equal(after, ctx.baseline.fiat, `a member credited their own fiat wallet (HTTP ${res.status})`);
      },
    },
    {
      name: 'PATCH user_staking_pools.rewards_earned does not change it',
      async run(ctx) {
        const res = await ctx.api(`/rest/v1/user_staking_pools?user_id=eq.${ctx.me}`, {
          method: 'PATCH',
          body: { rewards_earned: 424_242 },
          as: ctx.as.member,
          prefer: 'return=representation',
        });

        const after = ctx.scalar(
          `SELECT coalesce(sum(rewards_earned), 0)::text FROM public.user_staking_pools WHERE user_id = '${ctx.me}';`
        );
        ctx.expect.equal(
          after,
          ctx.baseline.rewards,
          `a member awarded themselves rewards (HTTP ${res.status})`
        );
      },
    },
    {
      name: 'PATCH user_staking_pools.staked_amount does not change it',
      async run(ctx) {
        // staked_amount is what the wallet's "staked" tile reads. Writable here,
        // it is a free credit on the screen even if nothing spendable moves.
        const res = await ctx.api(`/rest/v1/user_staking_pools?user_id=eq.${ctx.me}`, {
          method: 'PATCH',
          body: { staked_amount: AMOUNT, apy_rate: 99 },
          as: ctx.as.member,
          prefer: 'return=representation',
        });

        const after = ctx.scalar(
          `SELECT coalesce(sum(staked_amount), 0)::text FROM public.user_staking_pools WHERE user_id = '${ctx.me}';`
        );
        ctx.expect.equal(after, ctx.baseline.staked, `a member raised their own stake (HTTP ${res.status})`);
      },
    },
    {
      name: 'POST user_staking_pools cannot open a pool with a balance in it',
      async run(ctx) {
        const res = await ctx.api('/rest/v1/user_staking_pools', {
          method: 'POST',
          body: {
            user_id: ctx.me,
            pool_type: 'str',
            balance: AMOUNT,
            staked_amount: AMOUNT,
            apy_rate: 99,
          },
          as: ctx.as.member,
          prefer: 'return=representation',
        });

        const after = ctx.scalar(
          `SELECT count(*)::text FROM public.user_staking_pools WHERE user_id = '${ctx.me}';`
        );
        ctx.expect.equal(after, ctx.baseline.pools, `a member minted themselves a pool (HTTP ${res.status})`);
      },
    },
    {
      name: 'a member cannot write ANOTHER member\'s balances',
      async run(ctx) {
        const before = dbValue(ctx, 'user_wallets', 'arss_balance', `user_id = '${ctx.them}'`);
        const res = await ctx.api(`/rest/v1/user_wallets?user_id=eq.${ctx.them}`, {
          method: 'PATCH',
          body: { arss_balance: 1 },
          as: ctx.as.member,
          prefer: 'return=representation',
        });
        const after = dbValue(ctx, 'user_wallets', 'arss_balance', `user_id = '${ctx.them}'`);
        ctx.expect.equal(after, before, `a member wrote another member's wallet (HTTP ${res.status})`);
      },
    },
    {
      name: 'POST str_domains cannot mint a domain past the review path',
      async run(ctx) {
        // F-018 walked straight past the flow the UI describes: "Your request is
        // created as pending and reviewed by an operator." A member inserting
        // status:'minted' directly is the review path not existing.
        const res = await ctx.api('/rest/v1/str_domains', {
          method: 'POST',
          body: {
            user_id: ctx.me,
            domain_name: 'f018probe',
            domain_type: 'premium',
            status: 'minted',
          },
          as: ctx.as.member,
          prefer: 'return=representation',
        });

        const minted = ctx.scalar(
          `SELECT count(*)::text FROM public.str_domains
            WHERE domain_name = 'f018probe' AND status = 'minted';`
        );
        ctx.expect.equal(minted, '0', `a member minted a premium domain directly (HTTP ${res.status})`);
      },
    },

    /* ------------------------------------------------------- the generator */
    {
      name: 'no table carries a blanket "recovered own insert/update" policy',
      run(ctx) {
        // The root cause, asserted where it is cheapest to catch: a schema
        // regeneration that reintroduces the write half of the recovered
        // policies fails here immediately, rather than being found by probing
        // one table at a time.
        const rows = ctx.sql(
          `SELECT tablename, policyname, cmd
             FROM pg_policies
            WHERE schemaname = 'public'
              AND policyname LIKE 'recovered own%'
              AND cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL')
            ORDER BY 1, 2;`,
          { rows: true }
        );
        ctx.expect.ok(
          rows.length === 0,
          `${rows.length} blanket recovered write polic${rows.length === 1 ? 'y is' : 'ies are'} back — see F-018`,
          rows.slice(0, 10)
        );
      },
    },
    {
      name: 'user_wallets still has no UPDATE policy for authenticated at all',
      run(ctx) {
        // There is no legitimate browser path that updates a wallet row: every
        // balance change is a server-side function. The absence of the policy
        // is the control, so it is worth asserting the absence directly.
        const count = ctx.scalar(
          `SELECT count(*)::text FROM pg_policies
            WHERE schemaname = 'public' AND tablename = 'user_wallets'
              AND cmd IN ('UPDATE', 'ALL') AND 'authenticated' = ANY (roles);`
        );
        ctx.expect.equal(count, '0', 'an UPDATE policy on user_wallets has appeared for authenticated');
      },
    },

    /* -------------------------------------------------- the mirror test */
    {
      name: 'a member CAN still do the legitimate write: raise a staking request',
      run: async (ctx) => {
        // Without this, "deny everything" would pass every test above. The
        // member-facing flow the platform actually offers has to keep working.
        const res = await ctx.api('/rest/v1/staking_requests', {
          method: 'POST',
          body: {
            user_id: ctx.me,
            pool_type: 'str',
            request_type: 'stake',
            amount: 100,
            duration_months: 12,
            description: 'f018-legitimate-write',
          },
          as: ctx.as.member,
          prefer: 'return=representation',
        });

        ctx.expect.ok(
          res.status === 201,
          'a member could not raise a staking request — the platform is now unusable, not merely safe',
          { status: res.status, body: res.body }
        );

        const status = ctx.scalar(
          `SELECT status FROM public.staking_requests WHERE description = 'f018-legitimate-write';`
        );
        // And it lands PENDING: the member may ask, not decide.
        ctx.expect.equal(status, 'pending', 'a member-raised staking request did not land pending');
      },
    },
  ],
};
