-- =====================================================================
-- RECONCILIATION — resolving the overview's conflicts against live evidence
--
-- The first pass recorded 23 conflicts and resolved none, on the grounds that
-- choosing a winner would invent authority the document does not give. That was
-- half the job. Where a claim can be CHECKED, leaving it open is not caution,
-- it is laziness: the live hosts either answer or they do not.
--
-- So every conflict now carries a verdict and the evidence behind it:
--
--   verdict = 'resolved'      checked against a live source; one side wins
--   verdict = 'unverifiable'  checked, and the evidence does not settle it
--   verdict = 'open'          cannot be settled without the document's owner
--
-- `checked_at` and `evidence` say how, so the verdict can be re-tested rather
-- than trusted. Probes run 2026-08-20 from this machine.
-- =====================================================================

ALTER TABLE public.ecosystem_discrepancy
  ADD COLUMN IF NOT EXISTS verdict    text NOT NULL DEFAULT 'open'
    CHECK (verdict IN ('resolved','unverifiable','open')),
  ADD COLUMN IF NOT EXISTS resolution text,
  ADD COLUMN IF NOT EXISTS evidence   text,
  ADD COLUMN IF NOT EXISTS checked_at timestamptz;

-- ---------------------------------------------------------------------------
-- RESOLVED — a live probe settles it.
-- ---------------------------------------------------------------------------

-- The overview shows an explorer reporting 14M+ blocks at 0.4s. Neither host it
-- would run on answers. The explorer that DOES answer is strxplorer.com, which
-- is a different hostname from the one this platform is configured against.
UPDATE public.ecosystem_discrepancy SET
  verdict = 'resolved',
  resolution = 'This platform is correct. The chain is not reachable from here, so the overview''s block figures cannot be confirmed and anchoring stays disabled. The working explorer is strxplorer.com, not explorer.sourceless.net.',
  evidence = 'HTTPS probe: rpc.sourceless.net and explorer.sourceless.net both fail to resolve. strxplorer.com answers 200.',
  checked_at = now()
WHERE id = 'chain-live';

-- The deck's marketplace screenshot prices every domain in POL. The live site
-- does not mention POL at all.
UPDATE public.ecosystem_discrepancy SET
  verdict = 'resolved',
  resolution = 'This platform is correct. The POL pricing is a stale screenshot state; the live str.domains prices in STR. No POL figure should be carried across.',
  evidence = 'Rendered str.domains 2026-08-20: no occurrence of "POL"; STR present. The deck screenshot showed 59,101.7 / 100,000 / 300,000 POL.',
  checked_at = now()
WHERE id = 'marketplace-currency';

-- IgniteHeX's own status claim, checkable directly.
UPDATE public.ecosystem_discrepancy SET
  verdict = 'resolved',
  resolution = 'The overview is correct. The live site carries the same positioning and states the protocol is live.',
  evidence = 'Rendered ignitehex.com 2026-08-20: "Protocol live", "six-dimensional" and "zero-fee" all present. Shell reads "Stratus Control Hub".',
  checked_at = now()
WHERE id = 'zero-fee-scope';

-- The deck prints two different hostnames for the OS on two different pages.
INSERT INTO public.ecosystem_discrepancy
  (id, ordinal, kind, severity, subject, says_a, says_b, note, source_page,
   verdict, resolution, evidence, checked_at)
VALUES
('os-url', 165, 'internal', 'note', 'SourceLess OS address',
 'The domain registry lists os.sourceless.io.',
 'The product''s own brand plate and body text give os.sourceless.net.',
 'Two hostnames for one product, printed forty pages apart.', 'p84, p85 vs p125',
 'resolved',
 'os.sourceless.net is correct. The registry entry is wrong.',
 'HTTPS probe 2026-08-20: os.sourceless.net answers 200; os.sourceless.io does not resolve.',
 now())
ON CONFLICT (id) DO UPDATE SET
  verdict = EXCLUDED.verdict, resolution = EXCLUDED.resolution,
  evidence = EXCLUDED.evidence, checked_at = EXCLUDED.checked_at;

-- Every other published host, checked in one sweep. Recorded as a resolved
-- entry because "the ecosystem is reachable" is itself a claim worth testing.
INSERT INTO public.ecosystem_discrepancy
  (id, ordinal, kind, severity, subject, says_a, says_b, note, source_page,
   verdict, resolution, evidence, checked_at)
VALUES
('host-reachability', 5, 'platform', 'material', 'Which published hosts actually answer',
 'The overview publishes seventeen addresses across its pages and its domain registry.',
 'Fifteen answer. Two do not: rpc.sourceless.net and explorer.sourceless.net.',
 'Both failures are chain infrastructure. Every product site is up.', 'p125 and per-slide plates',
 'resolved',
 'The consumer-facing ecosystem is live. The chain endpoints are not, which is exactly why ledger anchoring on this platform is built and dormant rather than switched on.',
 'HTTPS probe 2026-08-20 of 17 hosts: 200 for sourceless.net, ignitehex.com, str.domains, ccoin.finance, strtalk.net, app.strtalk.net, wallet.sourceless.net, strxplorer.com, str4tus.sourceless.net, os.sourceless.net, slnn.io, areslang.com, aresmed.org, tech.sourceless.io, sourcelessmotorsport.com. No resolution for rpc.sourceless.net, explorer.sourceless.net.',
 now())
ON CONFLICT (id) DO UPDATE SET
  verdict = EXCLUDED.verdict, resolution = EXCLUDED.resolution,
  evidence = EXCLUDED.evidence, checked_at = EXCLUDED.checked_at;

-- ---------------------------------------------------------------------------
-- UNVERIFIABLE — checked, and the check does not settle it.
-- ---------------------------------------------------------------------------

UPDATE public.ecosystem_discrepancy SET
  verdict = 'unverifiable',
  resolution = 'Neither list is confirmed. The live site advertises no chain names at all, so the ten-chain screenshot and the four-chain prose are both unsupported by what is published today.',
  evidence = 'Rendered ignitehex.com 2026-08-20: none of ETH, BNB, SOL, MATIC, AVAX, ADA, TRX, DOT, NEAR or XRP appears in the page text.',
  checked_at = now()
WHERE id = 'bridge-chains';

UPDATE public.ecosystem_discrepancy SET
  verdict = 'unverifiable',
  resolution = 'The products are reachable, which is consistent with the "now live" claim, but a site answering 200 does not distinguish beta from general availability. The date conflict stands.',
  evidence = 'HTTPS probe 2026-08-20: areslang.com and aresmed.org both answer 200.',
  checked_at = now()
WHERE id IN ('ares-dates', 'os-dates');

UPDATE public.ecosystem_discrepancy SET
  verdict = 'unverifiable',
  resolution = 'sourcelessmotorsport.com is up, which shows the product exists but says nothing about whether the device ships. "Now available" and "testing phase" remain unreconciled.',
  evidence = 'HTTPS probe 2026-08-20: sourcelessmotorsport.com answers 200.',
  checked_at = now()
WHERE id = 'sl-ms1-availability';

-- ---------------------------------------------------------------------------
-- OPEN — no probe can settle these. They need the document's owner.
-- ---------------------------------------------------------------------------

UPDATE public.ecosystem_discrepancy SET
  verdict = 'open',
  resolution = 'Needs an owner decision. Whether eSTR, STR_STABLE and DOMAIN are internal instruments or should appear in the published model is not something a probe can answer.',
  checked_at = now()
WHERE id = 'token-count';

UPDATE public.ecosystem_discrepancy SET
  verdict = 'open',
  resolution = 'Needs a documented answer. A regulator, licence number and jurisdiction either exist or they do not, and neither the overview nor any live site states one.',
  checked_at = now()
WHERE id IN ('ccoin-regulator', 'compliance-absent', 'no-disclaimer');

UPDATE public.ecosystem_discrepancy SET
  verdict = 'open',
  resolution = 'Needs an owner decision: which token set is actually stakeable, and at what rates and lock-ups. This platform already carries fifteen disagreeing APY sources; the overview adds no authority to settle them.',
  checked_at = now()
WHERE id IN ('staking-tokens', 'yields-unquantified', 'governance-params');

UPDATE public.ecosystem_discrepancy SET
  verdict = 'open',
  resolution = 'Editorial. Pick one spelling and apply it across the document; this platform renders IgniteHeX, CCoin and AresLang throughout.',
  checked_at = now()
WHERE id IN ('product-naming', 'areslang-spelling', 'ghost-naming', 'strtalk-mobile-copy', 'ccoin-layer');

UPDATE public.ecosystem_discrepancy SET
  verdict = 'open',
  resolution = 'Needs the document''s owner. A patent is granted or it is not; an entity sits in a jurisdiction or it does not; two hardware products are one device or two.',
  checked_at = now()
WHERE id IN ('zk13-patent', 'entity-map', 'hardware-overlap', 'str-listing');

-- ---------------------------------------------------------------------------
-- Correct the component URL this evidence disproves.
-- ---------------------------------------------------------------------------
UPDATE public.ecosystem_component
   SET url = 'https://os.sourceless.net',
       status_note = 'Stage summary: debugging and testing; target Q3 2026. Its own slide says "post-Q1 2026" — see reconciliation.'
 WHERE id = 'sourceless-os';

UPDATE public.ecosystem_apps
   SET url = 'https://os.sourceless.net'
 WHERE slug = 'sourceless-os';
