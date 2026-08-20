-- =====================================================================
-- SOURCELESS ECOSYSTEM OVERVIEW
--
-- Source: "SourceLess Ecosystem Overview — Technology Achievements",
-- 127 pages, published at overview.sourceless.net. Every row below carries the
-- page it came from, so any statement on the ecosystem screen can be traced to
-- a slide rather than to somebody's memory of one.
--
-- THREE RULES THIS SCHEMA ENFORCES BY SHAPE:
--
--  1. `source_page` is NOT NULL on every claim. If a fact has no page, it does
--     not belong here. The deck is the authority; this is a rendering of it.
--
--  2. Status is what the deck says, not what we wish. The overview's own Stage
--     Summary (p6) is the authority, and where a later slide disagrees with it
--     that disagreement is recorded in `ecosystem_discrepancy` rather than
--     silently resolved.
--
--  3. Contradictions are DATA, not comments. The deck contradicts itself in
--     several places and contradicts this platform in others. Hiding that would
--     make the page a marketing artefact; surfacing it makes it a reconciliation
--     tool, which is what a beta is for.
-- =====================================================================

-- --------------------------------------------------------------- sections
CREATE TABLE IF NOT EXISTS public.ecosystem_section (
  id          text PRIMARY KEY,
  ordinal     integer NOT NULL,
  title       text NOT NULL,
  subtitle    text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------- components
CREATE TABLE IF NOT EXISTS public.ecosystem_component (
  id           text PRIMARY KEY,
  section_id   text NOT NULL REFERENCES public.ecosystem_section(id) ON DELETE CASCADE,
  ordinal      integer NOT NULL DEFAULT 100,
  name         text NOT NULL,
  summary      text NOT NULL,
  -- Verbatim from the deck's Stage Summary (p6) where it lists the component,
  -- otherwise from the component's own slide. 'unstated' is a real value: many
  -- components carry no status at all, and inventing one would be a claim.
  status       text NOT NULL DEFAULT 'unstated'
               CHECK (status IN ('live','beta','testing','rnd','planned','unstated')),
  status_note  text,
  url          text CHECK (url IS NULL OR url ~ '^https://'),
  source_page  integer NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ecosystem_component_section_idx
  ON public.ecosystem_component (section_id, ordinal);

-- ----------------------------------------------------------------- tokens
CREATE TABLE IF NOT EXISTS public.ecosystem_token (
  symbol       text PRIMARY KEY,
  ordinal      integer NOT NULL DEFAULT 100,
  name         text NOT NULL,
  role         text NOT NULL,
  -- FALSE means the platform's ledger carries this asset but the published
  -- overview does not name it. That gap is the point of the column: rendering
  -- all seven of our ledger assets as "the SourceLess token economy" would be a
  -- claim the source document does not make.
  in_overview  boolean NOT NULL DEFAULT true,
  source_page  integer,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------- discrepancies
CREATE TABLE IF NOT EXISTS public.ecosystem_discrepancy (
  id          text PRIMARY KEY,
  ordinal     integer NOT NULL DEFAULT 100,
  -- 'internal'  the deck disagrees with itself
  -- 'platform'  the deck disagrees with what this database actually holds
  -- 'unstated'  the deck asserts something without naming its basis
  kind        text NOT NULL CHECK (kind IN ('internal','platform','unstated')),
  severity    text NOT NULL DEFAULT 'note' CHECK (severity IN ('note','material')),
  subject     text NOT NULL,
  says_a      text NOT NULL,
  says_b      text NOT NULL,
  note        text,
  source_page text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- -------------------------------------------------------------------- RLS
-- Reference material. Any signed-in member may read it; nobody writes it
-- through PostgREST — it changes when the overview document changes, which is
-- a migration, not a form.
ALTER TABLE public.ecosystem_section      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ecosystem_component    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ecosystem_token        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ecosystem_discrepancy  ENABLE ROW LEVEL SECURITY;

DO $pol$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['ecosystem_section','ecosystem_component','ecosystem_token','ecosystem_discrepancy']
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I_read ON public.%I', t, t);
    EXECUTE format(
      'CREATE POLICY %I_read ON public.%I FOR SELECT TO authenticated USING (true)', t, t);
  END LOOP;
END $pol$;

-- =====================================================================
-- The overview's own table of contents (p3–p4).
-- =====================================================================
INSERT INTO public.ecosystem_section (id, ordinal, title, subtitle) VALUES
  ('presence',  1, 'Global presence',            'In continuous expansion'),
  ('stage',     2, 'Stage summary',              'What is live, and what is not'),
  ('chain',     3, 'Blockchain infrastructure',  'Protocols and development'),
  ('network',   4, 'Network',                    'And decentralised internet'),
  ('ai',        5, 'Artificial intelligence',    'And healthcare'),
  ('identity',  6, 'Digital identity',           'Communications and user applications'),
  ('defi',      7, 'DeFi and financial services','Tokens and digital commerce'),
  ('hardware',  8, 'Hardware and automotive',    'And specialised verticals'),
  ('domains',   9, 'Domains',                    'And digital identifiers')
ON CONFLICT (id) DO UPDATE
  SET ordinal = EXCLUDED.ordinal, title = EXCLUDED.title, subtitle = EXCLUDED.subtitle;

-- =====================================================================
-- Components. `summary` paraphrases the slide; `status` follows p6 where p6
-- names the component.
-- =====================================================================
INSERT INTO public.ecosystem_component
  (id, section_id, ordinal, name, summary, status, status_note, url, source_page) VALUES

-- ---- 03 blockchain infrastructure
('sourceless-blockchain','chain',10,'SourceLess Blockchain',
 'Hybrid, energy-efficient Web3 chain; the foundation for the STR economy and STR Domains. Proof of Stake.','unstated',NULL,'https://www.sourceless.net',8),
('sourceless-architecture','chain',20,'SourceLess Architecture',
 'Modular multi-layered framework. Proof of Stake with sub-second finality; elliptic-curve cryptography.','unstated','"Sub-second finality" is stated without a benchmark or TPS figure.',NULL,10),
('x3-multilayer','chain',30,'x3 Multilayer Architecture',
 'Three tiers: network infrastructure, execution, application. Layer one handles consensus, two smart-contract logic and data exchange, three user-facing apps and identifiers.','unstated',NULL,NULL,12),
('layer-1','chain',40,'SourceLess Layer 1',
 'The settlement layer. Every token transfer, contract execution and STR Domain operation finalises here.','unstated',NULL,NULL,14),
('ccoin-layer-2','chain',50,'CCoin Layer 2',
 'Secondary protocol for high-frequency finance: swaps, micro-payments, liquidity, private banking and hybrid-exchange operations. Syncs state and audit logs back to Layer 1.','unstated','The slide before it is titled "Ccoin Layer 1" — see discrepancies.',NULL,16),
('testnet','chain',60,'SourceLess TestNet',
 'Public sandboxed replica of the main environment for validating contracts and dApps before launch.','unstated',NULL,NULL,18),
('nodes-1mb','chain',70,'Nodes under 1MB',
 'Compact node with a binary footprint strictly under 1 MB, for edge devices, IoT hardware and personal systems.','unstated','The same slide says hardware requirements are "currently being benchmarked".',NULL,20),
('starw-vm','chain',80,'STARW Virtual Machines',
 'Proprietary compute engines executing contracts natively, addressed outside HTTP/HTTPS.','unstated',NULL,NULL,22),
('starw-worker','chain',90,'STARW Worker Nodes',
 'The core validation engine, running against the STARW VM environment. Sold through IgniteHeX.','unstated',NULL,'https://www.ignitehex.com',24),
('starw-super','chain',100,'STARW Super Nodes',
 'Premium tier above worker nodes: heightened validation, data-integrity oversight, network management.','unstated',NULL,'https://www.ignitehex.com',26),
('smart-contracts','chain',110,'Smart contracts via AresLang',
 'AresLang is the programming and validation environment for all contracts; Xplorer verifies deployed bytecode against source.','unstated',NULL,NULL,28),
('non-http','chain',120,'Non-HTTP/HTTPS addressing',
 'Blockchain-native identifiers resolving directly to assets or STARW VM instances, bypassing DNS.','unstated',NULL,NULL,30),
('p2p-hosting','chain',130,'Encrypted P2P hosting',
 'End-to-end encrypted hosting tied to the owner''s STR Domain; integrates with the SLNN mesh.','unstated',NULL,NULL,32),
('godcypher','chain',140,'GodCypher',
 'Proprietary cryptographic protocol; the security anchor for digital identity and data exchange.','unstated',NULL,NULL,34),
('zk13','chain',150,'ZK13 — Zero-Knowledge Layer 13',
 'Zero-knowledge validation of transactions, contracts and identity claims without disclosing content.','unstated','Described as a "patentable or provisional invention" — not stated as granted.',NULL,36),
('ghost','chain',160,'Ghost Protocol / Ghost Ledger',
 'Obfuscation mechanism plus the secondary chain or metadata index recording private state.','unstated','The deck says the two names are still used interchangeably and standardisation is underway.',NULL,38),
('wnft','chain',170,'wNFT Protocol',
 'Identity and asset framework. A user anchors their digital identity to a wNFT, verified through Xplorer.','unstated',NULL,NULL,40),
('forks','chain',180,'AI-chain forks',
 'Sub-ledgers and side-chains for AI training, data processing and niche services, interoperable with the core.','unstated','Code ownership and governance "currently being structured".',NULL,42),
('open-dev','chain',190,'Open development',
 'Public repositories: SourceLess Architecture, Blockchain, TestNet, Net, Ares Lang, GodCypher.','unstated',NULL,NULL,44),

-- ---- 04 network
('sourceless-net','network',10,'SourceLess Net',
 'Peer-to-peer decentralised internet built on node infrastructure rather than central servers.','unstated',NULL,NULL,46),
('slnn-mesh','network',20,'SLNN Mesh',
 'Self-healing wireless mesh bypassing ISPs. Every node is a relay; traffic reroutes automatically. Quantum-safe.','testing','Stage summary: active in test areas — Constanța, Romania.','https://www.slnn.io',48),
('slnn-node','network',30,'SLNN Mesh Node',
 'Hardware router performing packet routing, traffic validation and peer-to-peer hosting.','unstated',NULL,NULL,50),
('satellite','network',40,'Satellite Connectivity Layer',
 'Global backbone that backhauls isolated mesh nodes in remote, maritime and off-grid regions.','unstated','No constellation, satellite count or date is given.',NULL,52),
('linkdroid','network',50,'LinkDroid Router',
 'Hardware gateway into SLNN and SourceLess Net, encrypting and routing local traffic through the protocol.','unstated','Described in near-identical terms to the SLNN Mesh Node — see discrepancies.',NULL,54),

-- ---- 05 artificial intelligence
('ares-ai','ai',10,'ARES AI',
 'Intelligence suite across four domains: dynamic learning, global translation, strategic coaching, adaptive automation.','unstated',NULL,NULL,56),
('areslang','ai',20,'AresLang',
 'Language for the SourceLess chain: Python/TypeScript syntax, Solidity/Rust execution, quantum-safe crypto, zero-knowledge proofs, memory-safe, seismic-signal entropy.','beta','Stage summary: BETA — debugging and testing.','https://www.areslang.com',58),
('ares-llm','ai',30,'Ares AI LLM',
 'Configurable large language model operating inside user-owned digital spaces.','beta','Stage summary says BETA, target Q3 2026. Its own slide says it is live. See discrepancies.',NULL,60),
('ares-assistant','ai',40,'Ares AI Assistant',
 '24/7 assistant with Dealer and Support configurations.','beta','Stage summary says BETA, target Q3 2026. Its own slide says it is live. See discrepancies.',NULL,62),
('aresmed','ai',50,'AresMed',
 'Decentralised medical platform: vital-sign monitoring, encrypted doctor-patient channels, emergency tracking, AI-assisted diagnosis.','beta','Stage summary: BETA — debugging and testing.','https://www.aresmed.org',64),

-- ---- 06 digital identity (contents pp.67-85)
('str-domains','identity',10,'STR Domains 2.0',
 'Decentralised identity with lifetime ownership and no DNS dependency.','beta','Stage summary: BETA; marketplace and WalletConnect.','https://www.str.domains',67),
('str-bns','identity',20,'STR Domains BNS','Blockchain naming service for STR Domains.','unstated',NULL,NULL,68),
('str-auth','identity',30,'STR Domains Auth','Authentication against a held STR Domain.','unstated',NULL,NULL,69),
('str-marketplace','identity',40,'STR Domains Marketplace & Portfolio','Trading and portfolio view for domains.','unstated',NULL,NULL,70),
('domain-vault','identity',50,'Domain Vault & Vault Staking','Custody and staking for held domains.','unstated',NULL,NULL,73),
('strtalk-web','identity',60,'StrTalk Web','Encrypted messaging on the web.','live','Stage summary: live and functional.','https://www.strtalk.net',75),
('strtalk-mobile','identity',70,'StrTalk Mobile','Encrypted messaging on mobile.','beta','Stage summary: BETA — active development and testing.','https://www.app.strtalk.net',76),
('wallet-mobile','identity',80,'SourceLess Wallet Mobile','Native wallet for the ecosystem.','beta','Stage summary: BETA — active development and testing.','https://www.wallet.sourceless.net',78),
('wallet-engine','identity',90,'Multi-address / multi-chain wallet engine','One engine addressing several chains and addresses.','unstated',NULL,NULL,79),
('xplorer','identity',100,'SourceLess Xplorer','Explorer for transactions, Layer 2 financial data and contract verification.','unstated',NULL,'https://www.strxplorer.com',81),
('str4tus','identity',110,'STR4TUS Browser','Browser for the decentralised web.','beta','Stage summary: BETA — active development and testing.','https://www.str4tus.sourceless.net',83),
('sourceless-os','identity',120,'SourceLess OS','Operating system for the ecosystem.','testing','Stage summary: debugging and testing; target Q3 2026.','https://www.os.sourceless.io',85),

-- ---- 07 defi
('ignitehex','defi',10,'IgniteHeX — SourceLess Hybrid Exchange',
 'Six-dimensional DeFi protocol built on SourceLess. Swap, MultiBridge, Governance, A.R.E.S Engine and CCoin Bank in one surface.','live','Stage summary: protocol live; daily updates.','https://www.ignitehex.com',88),
('zero-fee-swaps','defi',20,'Zero-fee swaps','Swaps without protocol fees.','unstated',NULL,'https://www.ignitehex.com',90),
('multi-bridge','defi',30,'Multi-chain bridge','Cross-chain asset movement.','unstated',NULL,'https://www.ignitehex.com',92),
('pools','defi',40,'Liquidity, staking & governance pools','Pooled liquidity, staking positions and governance weight.','unstated',NULL,'https://www.ignitehex.com',94),
('voting','defi',50,'Decentralised voting & governance','On-chain proposals and voting.','unstated',NULL,'https://www.ignitehex.com',96),
('hex-marketplace','defi',60,'HEX Marketplace','Commerce hub for token packages and domains, with routes into CCoin services.','unstated',NULL,'https://www.ignitehex.com',98),
('multi-wallet','defi',70,'Multi-wallet integration','SourceLess Wallet natively, plus MetaMask, Trust Wallet and WalletConnect.','unstated',NULL,'https://www.ignitehex.com',100),
('node-sale','defi',80,'STARW node sale','Acquisition of Worker and Super Nodes; rewards follow consensus contribution and uptime.','unstated','No prices, counts or reward rates are stated.','https://www.ignitehex.com',102),
('ccoin-finance','defi',90,'CCoin Finance','Multi-currency accounts, crypto wallets, global payments, physical and virtual cards.','unstated','Described as "regulatory-compliant" with no regulator, licence or jurisdiction named.','https://www.ccoin.finance',104),
('ccoin-bank','defi',100,'CCoin Bank','Fiat bridge embedded in IgniteHeX: crypto-to-fiat conversion, accounts, payment processing.','unstated',NULL,'https://www.ignitehex.com',106),
('ccoin-card','defi',110,'CCoin Card & European IBAN','European IBAN on SEPA plus a global Visa card, converting at the point of sale.','unstated',NULL,'https://www.ignitehex.com',108),

-- ---- 08 hardware
('motorsport','hardware',10,'SourceLess Motorsport',
 'Immutable vehicle telemetry: real-time acquisition, positioning and incident data for forensic and insurance use.','testing','Stage summary: testing period.','https://www.sourcelessmotorsport.com',113),
('sl-ms1','hardware',20,'SL-MS1 Vehicle Device',
 'Turns a vehicle into a chain node over a 16-pin J1962 interface on 12V DC, recording telemetry to the ledger.','testing','One slide says "NOW AVAILABLE", the facing slide says testing phase. See discrepancies.','https://www.sourcelessmotorsport.com',115),
('fds','hardware',30,'Fault Detection Signals (FDS)',
 'Detects anomalies and writes cryptographically signed, timestamped fault records to the chain.','testing',NULL,'https://www.sourcelessmotorsport.com',117),
('telemetry','hardware',40,'Telemetry & incident recording',
 'Streams RPM, speed, temperatures, sensor inputs and emissions; a tamper-proof black box.','testing',NULL,'https://www.sourcelessmotorsport.com',119),
('vehicle-node','hardware',50,'Vehicle node & OTA updates',
 'Each device is an independent node; firmware arrives over the air through smart contracts.','testing',NULL,'https://www.sourcelessmotorsport.com',121),
('sourceless-tech','hardware',60,'SourceLess Tech',
 'Privacy-first hardware: computing devices, secure handsets and networking equipment.','rnd','Stage summary: R&D and advanced validation.','https://www.tech.sourceless.io',123),
('planned-devices','hardware',70,'Planned devices',
 'SECU Laptop, Reflection Smartphone, Ocean Tab, Sunstorm Smartphone, RIFT Smartphone.','planned','Labelled "Planned Devices"; no specs, prices or dates given.','https://www.tech.sourceless.io',124)

ON CONFLICT (id) DO UPDATE SET
  section_id = EXCLUDED.section_id, ordinal = EXCLUDED.ordinal, name = EXCLUDED.name,
  summary = EXCLUDED.summary, status = EXCLUDED.status, status_note = EXCLUDED.status_note,
  url = EXCLUDED.url, source_page = EXCLUDED.source_page;

-- =====================================================================
-- The token economy (p110), plus the ledger assets the overview omits.
-- =====================================================================
INSERT INTO public.ecosystem_token (symbol, ordinal, name, role, in_overview, source_page) VALUES
  ('STR',  10, 'SourceLess Token',
   'The core utility asset, intrinsically linked to STR Domains and digital identity; the primary medium for accessing and managing a digital presence on the chain.', true, 110),
  ('CCOS', 20, 'CCOS Token',
   'Specialised utility token for internal transactions, service payments and value transfer between users and platform services.', true, 110),
  ('ARSS', 30, 'ARSS',
   'Liquidity and reward module asset, used for staking and governance participation.', true, 110),
  ('WSTR', 40, 'wSTR',
   'Liquidity and reward module asset; frequently deployed as an incentivised reward for active contributors and liquidity providers.', true, 110),
  ('ESTR', 50, 'eSTR',
   'Carried by this platform''s ledger. Not named anywhere in the published overview.', false, NULL),
  ('STR_STABLE', 60, 'STR Stable',
   'Carried by this platform''s ledger. Not named anywhere in the published overview.', false, NULL),
  ('DOMAIN', 70, 'DOMAIN',
   'Carried by this platform''s ledger. Not named anywhere in the published overview.', false, NULL)
ON CONFLICT (symbol) DO UPDATE SET
  ordinal = EXCLUDED.ordinal, name = EXCLUDED.name, role = EXCLUDED.role,
  in_overview = EXCLUDED.in_overview, source_page = EXCLUDED.source_page;

-- =====================================================================
-- Discrepancies. Shown on the page, not buried here.
-- =====================================================================
INSERT INTO public.ecosystem_discrepancy (id, ordinal, kind, severity, subject, says_a, says_b, note, source_page) VALUES
('ares-dates', 10, 'internal', 'material', 'Ares AI LLM and Assistant release dates',
 'Stage summary: BETA, target Q3 2026.',
 'Their own slides: originally targeted Q1 2026, and now live and operational.',
 'The same document gives two different quarters and two different states. Neither has been verified against the running service.', 'p6 vs p60, p62'),

('ccoin-layer', 20, 'internal', 'note', 'CCoin layer number',
 'Slide title reads "Ccoin Layer 1".',
 'Its own body slide and the table of contents both read "CCoin Layer 2".',
 'Two sources against one. Treated as Layer 2 here.', 'p15 vs p16, p3'),

('sl-ms1-availability', 30, 'internal', 'material', 'SL-MS1 vehicle device availability',
 'Product ticker: "SL-MS1 DEVICE · NOW AVAILABLE".',
 'The facing slide: "Currently in its testing phase". Stage summary: "Testing period".',
 'Availability and testing status are asserted one page apart.', 'p113 vs p114'),

('token-count', 40, 'platform', 'material', 'How many tokens the economy has',
 'The overview names four: STR, CCOS, ARSS, wSTR.',
 'This platform''s ledger carries seven, adding eSTR, STR_STABLE and DOMAIN.',
 'The three extra assets appear nowhere in the 127-page overview, not even in its contents. Either they are internal instruments the overview does not cover, or they have no counterpart in the published model.', 'p110 vs ledger_asset'),

('chain-live', 50, 'platform', 'material', 'Whether the SourceLess chain is reachable',
 'The overview shows a live block explorer: 14M+ blocks, 0.4s block time, <1MB node size, 256-bit encryption.',
 'This platform has the chain configured but disabled, and its RPC host does not resolve.',
 'Ledger anchoring is built and dormant here. The overview''s figures come from a product screenshot rather than a specification slide.', 'p114 vs ledger_anchor_chain'),

('str-listing', 60, 'unstated', 'material', 'STR exchange listing',
 'Stage summary: "STR token - CEX listing — Status must be confirmed".',
 'No exchange, pair or date is named anywhere in the document.',
 'The overview declines to assert a listing. Any live STR price shown on this platform is a stronger claim than its own source document makes.', 'p6'),

('ccoin-regulator', 70, 'unstated', 'material', 'CCoin Finance regulatory status',
 'CCoin Finance is described as "regulatory-compliant".',
 'No regulator, licence number, or jurisdiction of authorisation is named anywhere in the document.',
 'The only jurisdictional reference in the financial section is SEPA, which is a payment area rather than an authorisation.', 'p104'),

('zk13-patent', 80, 'unstated', 'note', 'ZK13 intellectual property status',
 'Described as "a patentable or provisional invention".',
 'No granted patent, application number or filing date is given.',
 'Patentable is not patented. Worth stating precisely wherever this is repeated.', 'p36'),

('ghost-naming', 90, 'internal', 'note', 'Ghost Protocol versus Ghost Ledger',
 'The deck uses both names for the same area.',
 'It states the terms are "currently used interchangeably" and that standardisation is "underway".',
 'They are not two settled, separately shipping components; the document says so itself.', 'p38'),

('hardware-overlap', 100, 'internal', 'note', 'SLNN Mesh Node versus LinkDroid Router',
 'Both are described as hardware routers and gateways into SLNN and SourceLess Net.',
 'The document never says whether they are one device, two models, or one contained in the other.',
 'Listed separately here because the deck lists them separately, not because a distinction is established.', 'p50 vs p54'),

('areslang-spelling', 110, 'internal', 'note', 'AresLang spelling',
 'Written "ARES Lang" on the GodCypher and repositories slides.',
 'Written "AresLang" on its own slides and in the contents.',
 'Rendered as "AresLang" here, following the component''s own pages.', 'p34, p44 vs p57, p58'),

('no-disclaimer', 120, 'unstated', 'material', 'Investment and forward-looking disclaimers',
 'The overview makes forward-looking product and availability claims throughout.',
 'It carries no forward-looking-statement disclaimer, no investment-risk disclaimer, no legal entity and no jurisdiction of incorporation.',
 'The global presence map names eight territories but attaches no company to any of them.', 'p5, p127'),

('entity-map', 130, 'unstated', 'note', 'Global presence entities',
 'Eight territories are mapped: USA-Delaware, BVI, Luxembourg, Switzerland, Romania, Cyprus, UAE, Singapore.',
 'No company name, legal form, role or registration is attached to any of them.',
 'The map shows where, never who or what.', 'p5'),

('bridge-chains', 140, 'internal', 'material', 'How many chains the bridge supports',
 'The product screenshot lists ten: ETH, BNB, SOL, MATIC, AVAX, ADA, TRX, DOT, NEAR, XRP.',
 'The bridge''s own description slide names four: Ethereum, BNB/BSC, Solana, Polygon.',
 'Same product, same document, five pages apart.', 'p87 vs p92'),

('staking-tokens', 150, 'internal', 'material', 'Which tokens are stakeable',
 'The pools slide: "staking STR, CCOS, and ARSS tokens".',
 'The token economy slide: ARSS and wSTR are the staking and governance assets.',
 'One set includes CCOS and excludes wSTR; the other does the reverse. Only ARSS appears in both.', 'p94 vs p110'),

('os-dates', 160, 'internal', 'note', 'SourceLess OS timing',
 'Stage summary: debugging and testing, target Q3 2026.',
 'Its own slide: "moving through its post-Q1 2026 development phase".',
 'Two different quarters for the same product.', 'p6 vs p85'),

('marketplace-currency', 170, 'platform', 'material', 'What domains are priced in',
 'The domain marketplace prices every listing in POL (Polygon) — 59,101.7 POL, 100,000 POL, 300,000 POL.',
 'This platform''s marketplace and ledger price in STR and fiat. POL is not a ledger asset here.',
 'At the implied rate of about $0.0775 per POL, those listings run $4,580 to $23,250. Nothing on this platform reconciles to POL.', 'p71'),

('zero-fee-scope', 180, 'unstated', 'material', 'What "zero-fee" covers',
 'Swaps are presented as zero-fee, funded by domain vault staking.',
 'The text says costs are decoupled "from the platform itself" — it never claims network or gas costs are zero.',
 'Restating this as "no fees" would overstate the source. Platform fee and network fee are different things.', 'p90'),

('yields-unquantified', 190, 'unstated', 'material', 'Staking yields and lock-ups',
 'The pools slide promises "competitive, tiered yields" and "strategic lock-up periods".',
 'No tier, no rate, no duration and no number of any kind appears on that slide or anywhere near it.',
 'This platform has fifteen disagreeing APY sources of its own. The overview adds no authority to settle them.', 'p94'),

('governance-params', 200, 'unstated', 'note', 'Governance parameters',
 'Voting is stake-weighted through an "IgniteHeX DAO" over pool parameters, treasury and fees.',
 'No quorum, proposal threshold, voting period, timelock or multisig is stated.',
 'The mechanism is named but not specified.', 'p96'),

('product-naming', 210, 'internal', 'note', 'Product name spelling',
 'The exchange is written IgniteHEX, HeXIgnite, HeXIgnitE and "Hex Ignite" in different places.',
 'CCoin and Ccoin both appear; the marketplace title reads "Portofolio"; a divider reads "Decentralized Volting".',
 'Rendered here as IgniteHeX and CCoin throughout.', 'p87, p88, p70, p95'),

('strtalk-mobile-copy', 220, 'internal', 'note', 'StrTalk Mobile description',
 'The mobile slide''s opening paragraph describes "StrTalk Web".',
 'It is copied verbatim from the preceding web slide.',
 'Also note mobile states STR Domain integration in the future tense ("will be integrated") while web states it in the present.', 'p75 vs p76'),

('compliance-absent', 230, 'unstated', 'material', 'Compliance framework',
 'The overview covers banking, IBANs, cards, staking yields and investment products.',
 'MiCA, KYC, AML, audits, custody arrangements and licensing appear nowhere in all 127 pages.',
 'This platform stores MiCA terms, investor classification and PEP declarations. The overview offers no basis for any of it.', 'whole document')

ON CONFLICT (id) DO UPDATE SET
  ordinal = EXCLUDED.ordinal, kind = EXCLUDED.kind, severity = EXCLUDED.severity,
  subject = EXCLUDED.subject, says_a = EXCLUDED.says_a, says_b = EXCLUDED.says_b,
  note = EXCLUDED.note, source_page = EXCLUDED.source_page;

-- =====================================================================
-- The launcher's app list, completed from the overview's own domain
-- registry (p125). It listed five; the document names fifteen.
-- =====================================================================
INSERT INTO public.ecosystem_apps (slug, name, url, description, category, embeddable, sort_order, active) VALUES
  ('sourceless',     'SourceLess',         'https://www.sourceless.net',            'The ecosystem''s main site.',                         'core',         false, 5,   true),
  ('xplorer',        'SourceLess Xplorer', 'https://www.strxplorer.com',            'Block explorer and contract verification.',           'core',         false, 25,  true),
  ('strtalk-web',    'StrTalk Web',        'https://www.strtalk.net',               'Encrypted messaging.',                                'social',       false, 50,  true),
  ('strtalk-mobile', 'StrTalk Mobile',     'https://www.app.strtalk.net',           'Encrypted messaging on mobile.',                      'social',       false, 55,  true),
  ('wallet',         'SourceLess Wallet',  'https://www.wallet.sourceless.net',     'Native wallet for the ecosystem.',                    'finance',      false, 45,  true),
  ('areslang',       'AresLang',           'https://www.areslang.com',              'The language for SourceLess smart contracts.',        'developer',    false, 70,  true),
  ('aresmed',        'AresMed',            'https://www.aresmed.org',               'Decentralised medical platform.',                     'health',       false, 75,  true),
  ('slnn',           'SLNN Mesh',          'https://www.slnn.io',                   'Decentralised wireless mesh network.',                'connectivity', false, 65,  true),
  ('sourceless-tech','SourceLess Tech',    'https://www.tech.sourceless.io',        'Privacy-first hardware.',                             'hardware',     false, 80,  true),
  ('sourceless-os',  'SourceLess OS',      'https://www.os.sourceless.io',          'Operating system for the ecosystem.',                 'core',         false, 85,  true),
  ('str4tus',        'STR4TUS Browser',    'https://www.str4tus.sourceless.net',    'Browser for the decentralised web.',                  'core',         false, 90,  true),
  ('motorsport',     'SourceLess Motorsport','https://www.sourcelessmotorsport.com','Blockchain-secured vehicle telemetry.',               'automotive',   false, 95,  true),
  ('ignitehex',      'IgniteHeX',          'https://www.ignitehex.com',             'The SourceLess hybrid exchange.',                     'finance',      false, 15,  true)
ON CONFLICT (slug) DO NOTHING;
