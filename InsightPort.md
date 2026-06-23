# InsightPort — Lineage, Ecosystem Status, Component Versions & Porting

Companion to [InsightBlock.md](InsightBlock.md) (the central operations reference)
and [InsightFix.md](InsightFix.md) (crash signatures and staged hardening); the
[README](README.md) holds the documentation map. This
document covers **where the code came from, what state the ecosystem is in, what
versions run in production, and what is worth porting in** — plus an appendix on the
range of explorer alternatives, focused on Blockbook.

---

## 1. Source repos & where they live

The explorer is a **bitcore-node** stack assembled from `zerocurrencycoin`
(Zero) repos under `github.com/orgs/zerocurrencycoin`. The deployed install in
`/home/ubuntu/zero/mynode` pulls **five** Zero-authored packages into
`node_modules`. Four are direct deps in `mynode/package.json`; the fifth
(`bitcore-message-zero`) is a transitive dep of `insight-api-zero`. All five
are installed straight from GitHub (`_from: github:zerocurrencycoin/...`),
each pinned to a specific commit.

| Package (node_modules) | Version | Direct? | Role | Pinned commit |
|---|---|---|---|---|
| **bitcore-node-zero** | 3.1.2 | direct | Main node/orchestrator; spawns `zerod`, loads services. Runs as the `bitcore` process | `acb3b1d` |
| **insight-api-zero** | 0.4.3 | direct | REST API (blocks, txs, addresses, charts, price) | `dec6b29` |
| **insight-ui-zero** | 0.4.0 | direct | Web frontend (explorer UI), port 3001 | `7a38590` |
| **bitcore-lib-zero** | 0.13.19 | direct | Shared lib — address/tx/block parsing primitives | `b7f125d` |
| **bitcore-message-zero** | 1.0.2 | transitive (via insight-api-zero) | Message sign/verify helper for Zero keys | `929c1c2` |

All five live under `/home/ubuntu/zero/mynode/node_modules/<name>/` — this is
the **deployed/running** code and the actual edit target for the fixes
(distinct from the local working-copy clones).
`bitcore-message-zero` is not in any crash path; the crash-relevant code is in
`bitcore-lib-zero` (parser), `bitcore-node-zero` (spawn/ZMQ), and
`insight-api-zero` (handler/API).

Supporting repos in the org: **bitcore-build-zero** (build tooling),
**bitcoind-rpc** (RPC client to `zerod`), **blockbook** (Trezor stack, see the
appendix).

### Cloned locally
The four direct-dep repos are cloned into the local working copy:
```
bitcore-node-zero/  insight-api-zero/  insight-ui-zero/  bitcore-lib-zero/
```
Each has an `upstream` remote added pointing at `ProphetAlgorithms/<repo>.git`.
The transitive `bitcore-message-zero` is not cloned locally (it exists only in
the deployed install); clone `zerocurrencycoin/bitcore-message-zero` if it needs
review.

Also cloned into the same directory for evaluation: `blockbook/` (Trezor, the
multi-coin explorer) and `lbe-hellcatz/` (LBE, the lightweight equihash
explorer). Provenance for both is in the appendix.

### `package.json` (mynode) dependencies
```json
"dependencies": {
  "bitcore-lib-zero":  "zerocurrencycoin/bitcore-lib-zero",
  "bitcore-node-zero": "zerocurrencycoin/bitcore-node-zero",
  "insight-api-zero":  "github:zerocurrencycoin/insight-api-zero",
  "insight-ui-zero":   "github:zerocurrencycoin/insight-ui-zero"
}
```

---

## 2. Runtime & platform versions

| Component | Version | Notes |
|---|---|---|
| Node (nvm) | **v8.17.0** | last 8.x; **EOL 2019-12-31**; the running runtime |
| Node (system) | v8.10.0 | `/usr/bin/node`; **unused** |
| OS | Ubuntu 18.04.4 LTS (bionic) | |
| Kernel | Linux 4.15.0-76-generic x86_64 | |
| systemd | 237 | see the [InsightBlock.md §4.2](InsightBlock.md#42-systemd-model) systemd notes for v237 gotchas |
| nginx | 1.14.0 | TLS terminator / reverse proxy |
| zerod identity | version 3030106, subversion `/Ambrym:3.3.1-beta7(bitcore)/`, protocol 170009 (Sapling) | |

### Node-8 wall (the central upgrade constraint)

Node 8.17 is welded to OpenSSL 1.0.2. The practical consequences run through
the whole stack:

| Target | What it buys | Cost |
|---|---|---|
| Node 10 | OpenSSL 1.1.1 — minimum clean CA fix (the [crash #4](InsightFix.md) cert problem disappears at the runtime level) | The hard wall: forced native rebuilds of `zeromq`, `leveldown`, `secp256k1`, plus `Buffer` API cleanup |
| Node 14 | Better landing than 10; longer support runway | Same native-rebuild + Buffer work as 10 |

- **8 → 10 is the hard jump** — everything past it is comparatively smooth. The
  native addons (`zeromq`, `leveldown`, `secp256k1`) must be rebuilt against the
  new ABI, and deprecated `Buffer` constructors must be cleaned up.
- The AddTrust External CA Root expired **2020-05-30**; because Node 8 carries a
  frozen CA bundle, outbound TLS to modern endpoints fails locally even though
  the remote certs are valid. The [crash #4 fix](InsightFix.md) works around this
  at the application layer (load the OS CA bundle); a Node 10+ upgrade fixes it
  at the runtime layer. **The two are independent** — the staged app-level fix
  is correct regardless of any future Node move.

### Dependency-modernization reality check

Porting from siblings does **not** modernize the stack. Pirate (the best porting
source, below) pins the **same** ancient deps as Zero: `bn.js =2.0.4`,
`elliptic =3.0.3`, `lodash =3.10.1`, and `insight-api` engines `node >=0.12.0`.
Cherry-picking from Pirate gets you chain logic, not a Node-version or dependency
upgrade. Moving off Node 8.17 is a separate, larger effort — or a reason to
favor the Blockbook/modern path long-term — and will not fall out of sibling
cherry-picks.

---

## 3. Fork lineage & upstream status

### Lineage
```
str4d/*-zcash  →  …  →  ProphetAlgorithms/*  →  zerocurrencycoin/*  (what runs in production)
```
- The **direct parent / real upstream is `ProphetAlgorithms/*`**, not str4d and not
  zerocurrencycoin. ProphetAlgorithms is the last active maintainer of *this* lineage.
- All forks default to branch `master`.

### Divergence: `zerocurrencycoin` (local) vs `ProphetAlgorithms/master`
| Repo | Behind | Ahead | Local HEAD | Upstream HEAD |
|---|---|---|---|---|
| bitcore-node-zero | **49** | 16 | `acb3b1d7` 2020-08-09 "fix zero.conf" | `fb503ecc` 2021-05-05 |
| insight-api-zero  | **34** | 33 | `dec6b29` 2020-07-16 "update readme" | `d28efeb` 2021-05-05 |
| insight-ui-zero   | **53** | 10 | `7a38590` 2020-07-15 "revert" | `48cea90` 2021-05-07 |
| bitcore-lib-zero  | **22** | 8  | `b7f125d` 2020-07-15 "remove reserved" | `c72c9fe` 2021-05-05 |

**Both directions matter** — the forks have *diverged*, not merely fallen behind.
A blind merge would **regress** Zero-specific features.

### What UPSTREAM has that Zero lacks (candidate improvements)
- **bitcore-node-zero**: `bitcoind.js` spawn/retry fixes, `bitcoin.conf`/`default-base-config.js`
  updates, docs (`upgrade.md`, `development.md`). *Relevant to the `startRetryCount: 60` workaround.*
- **insight-api-zero**: `currency.js` price-API rewrite, `charts.js`/`status.js`/`transactions.js`
  fixes, `saplingblocks.js` handling. (diffstat: ~9 files, +73/-58)
- **insight-ui-zero**: UI/CSS refresh, new assets, i18n (`de_DE`, `es`, `ja` `.po`), currency display.
- **bitcore-lib-zero**: `networks.js` fixes; sapling/witness primitives
  (`spenddescription.js`, `outputdescription.js`, `jsdescription.js`).

### What ZERO has that upstream lacks (would be lost in a naive merge)
From `zerocurrencycoin` ahead-commits (esp. insight-api, 33 ahead):
- **CoinGecko** price feed (`update currency.js to use coingecko`)
- **`getsupply`** endpoint + **zeronode stats**
- Sapling/Overwinter support commits, `getSaplingBlocks`, `getsaplingwitness`, `finalsaplingroot`
- `transformInvTransaction` fixes

Caution: Upstream's `currency.js` rewrite **conflicts** with Zero's CoinGecko work — needs a
manual 3-way reconcile, NOT a merge.

### "Recent Prophet push" — explained (was a red herring)
`ProphetAlgorithms/bitcore-lib-zero` showed a **2026-02-22** `pushedAt`, looking freshly
maintained. It is **not** human activity:
```
upstream/dependabot/npm_and_yarn/bn.js-5.2.3   2026-02-22  f6c216e  Bump bn.js from 2.0.4 to 5.2.3
```
- A **Dependabot** security PR on a *side branch*. `master` is still frozen at 2021-05-05 (`c72c9fe`).
- GitHub's `pushedAt` reflects the newest push across *all* branches → made a dead repo look alive.
- The bump itself is legit & isolated (bn.js 2.0.4 → 5.2.3 fixes a ReDoS-class issue) — safe to cherry-pick.

**Bottom line: all four upstreams are effectively dead since May 2021.**

---

## 4. Parallel Zcash-family projects (comparative)

### The "Insight fork" (term used throughout)

Nearly every Zcash-clone explorer is the same codebase: the str4d/Zcash port of BitPay's Insight stack, four coupled npm packages — `bitcore-lib-*` (parsing primitives), `bitcore-node-*` (full-node orchestrator that spawns the coind), `insight-api-*` (REST API), and `insight-ui-*` (web frontend). Each project suffixes the coin name (`-zero`, `-pirate`, `-zen`, `-zclassic`) and patches it for their chain. In the table below, "Insight fork" means that whole four-repo stack; the Stack column only flags where a project deviates (a different stack, extras, or none).

### Caveat on "last commit" dates

GitHub `pushedAt` and a single recent commit do not mean a repo is actively maintained. Verify what the recent activity actually is before judging. Examples found here: ProphetAlgorithms looked alive at 2026-02-22 but it was a lone Dependabot bn.js bump on a side branch (master frozen 2021); Ycash repos show recent dates but much is automated/dependency churn; Horizen's 2024 commits are ZEN sidechain/pool config, not portable fixes. The status column reflects what the commits contain, not just their dates.

### Unified table

Org links the GitHub organization home; Insight repos names the specific repos (or what is used instead).

| Project (coin) | Org | Insight repos / stack | Stack | Status (verified) |
|---|---|---|---|---|
| Zero (ZER) — ours | [zerocurrencycoin](https://github.com/orgs/zerocurrencycoin/repositories) | `bitcore-lib-zero`, `bitcore-node-zero`, `insight-api-zero`, `insight-ui-zero` | Insight fork | Frozen 2021; Node 8.17 (EOL 2019) |
| upstream of ours | [ProphetAlgorithms](https://github.com/ProphetAlgorithms) | same four `*-zero` repos | Insight fork | Master frozen May 2021; only a Dependabot side-branch since |
| Zclassic (ZCL) — our ancestor | [z-classic](https://github.com/z-classic) | `bitcore-lib-zclassic`, `bitcore-node-zclassic`, `insight-api-zclassic`, `insight-ui-zclassic` | Insight fork | Dead since Feb 2018 (pre-Sapling) |
| Pirate Chain (ARRR) | [PirateNetwork](https://github.com/PirateNetwork) | `bitcore-lib-pirate`, `bitcore-node-pirate`, `insight-api-pirate`, `insight-ui-pirate` | Insight fork | Active; api 2024-10 commit is real tx-parsing work (tx v5) |
| Horizen (ZEN) | [HorizenOfficial](https://github.com/HorizenOfficial) | `bitcore-lib-zen`, `bitcore-node-zen`, `insight-api-zen`, `insight-ui-zen` | Insight fork | Maintained to 2024, but recent commits are ZEN sidechain/pool config; **migrated off PoW to Base/EVM July 2025 — no longer a reference** |
| Komodo + asset chains | [KomodoPlatform](https://github.com/KomodoPlatform) · [DeckerSU](https://github.com/DeckerSU) | Insight plus custom komodod dev branch (txindex/addressindex/timestampindex/spentindex/zmq) plus Electrum for search; `komodo-explorers-install` | Insight + extras | Maintained via install scripts |
| TENT (TENT, formerly SnowGem/XSG) | [TENTOfficial](https://github.com/TENTOfficial) | `tent-insight`, `insight-api-tent`, `insight-ui-tent`, `bitcore-node-tent`, `bitcore-lib-tent` | Insight fork | Genuine Zcash-family Insight fork; frozen 2020-2022 (api last pushed 2022-10); no open issues/PRs |
| Hush (HUSH) | [MyHush](https://github.com/MyHush) | `TheTrunk/explorer-hush` — Iquidus Explorer 1.6.1 (MongoDB) | Different stack (not Insight) | Older/simpler |
| Firo (FIRO, formerly Zcoin/XZC) | [firoorg](https://github.com/firoorg) | No Insight/bitcore; Bitcoin-derived node, Blockbook config `firo.json` | Not a Zcash/Equihash fork | Out of family; Bitcoin lineage, FiroPOW (ProgPOW), Spark/Lelantus, not Sapling |
| Ycash (YEC) | [ycashfoundation](https://github.com/ycashfoundation) | No Insight/bitcore; uses `lightwalletd`, own `zebra` fork, `rosetta-bitcoin` | Modern Rust stack | Chain alive; explorer modernized — see 4.1 |
| Zcash core (ZEC) | [zcash](https://github.com/zcash) · [ZcashFoundation](https://github.com/ZcashFoundation) | Moving off Insight toward Blockbook; node moving to zebrad + Zaino | Modern Rust stack | zcashd still released (v6.20.0, 2026-06) but on a path to retirement — see 4.2 |

On TENT (formerly SnowGem / XSG): this is a genuine member of the family. The TENTOfficial org carries the full Insight fork (`tent-insight`, `insight-api-tent`, `insight-ui-tent`, `bitcore-node-tent`, `bitcore-lib-tent`), all original (not GitHub forks) repos seeded from the same str4d/Zcash Insight lineage. They are frozen (bitcore repos 2020-12, insight-api last pushed 2022-10) with no open issues or PRs, so it is a portable-in-principle sibling but offers nothing newer than what Pirate already has.

On Firo (formerly Zcoin / XZC): included for completeness, but it is NOT in the Zcash/Equihash family and is not a porting candidate. Firo is a Bitcoin-derived chain — its privacy comes from the Spark protocol (and earlier Lelantus/Sigma/Zerocoin), its Proof-of-Work is FiroPOW (a ProgPOW variant), and it uses LLMQ ChainLocks. It has no Sapling, no Equihash, and no bitcore/Insight repos. The only overlap with this project is that Blockbook ships a `firo.json` coin config, which is why it surfaces in explorer comparisons. Do not treat Firo code as relevant to Zero's Sapling/Equihash stack.

### Maintenance ranking of portable Insight siblings (most to least useful as a source)

1. Pirate (ARRR). `insight-ui-pirate` pushed 2026-06-11, `insight-api-pirate` 2024-10-13, `bitcore-lib-pirate` 2024-11-01. The recent api commit is "add transaction version 5" — genuine tx-parsing/consensus work — plus Sapling handling (`saplingblocks.js`, `witness.js`). Closest architectural match to Zero (privacy-default Sapling). Branches: `master`, `generic-ui`, `saplingroot`. Primary porting source.
2. Horizen (ZEN). `insight-api-zen` 2024-02-29, `insight-ui-zen` 2023-09-13, from a funded org with the most professional codebase. But its distinctive recent commits are ZEN-specific config, and it has since left the PoW chain entirely (below), so it is a one-time selective-scavenging source, not a main line.
3. Zclassic (ZCL). Zero's literal ancestor, but the explorer repos are frozen Feb 2018 (pre-Sapling). Historical reference only.

### Does Horizen have relevant fixes not in Pirate? Largely no.

From the actual recent commit logs:

- Horizen `insight-api-zen` (to 2024-02): recent work is almost entirely ZEN-chain config — "Add Gobi/PreGobi sidechain names", "add Horizen EON as a known sidechain", `sidechains.json` id updates, and `pools.json` mining-pool refreshes. These are EON/Gobi sidechain and pool metadata, not portable bug/security fixes, and they do not apply to Zero (Zero has no sidechains).
- Pirate `insight-api-pirate` (to 2024-10): newest commit is "add transaction version 5" — real tx-parsing/consensus work — plus Sapling handling.

Conclusion: Horizen is the best-engineered sibling and worth scanning for clean generic fixes in `bitcore-lib-zen`/`bitcore-node-zen` (parsing, spawn, networks), but its distinctive recent activity is ZEN-specific. Pirate remains the primary porting source.

### 4.1 Ycash (YEC) — current status

Chain still live. Halving schedule documented through 2040 (6th halving at block 9,000,000); the 2nd halving made the 5% dev-fund optional. Public price data thinned out after roughly July 2025, likely exchange delisting rather than chain death. The explorer/stack abandoned Insight entirely for a modern Rust stack: [`lightwalletd`](https://github.com/ycashfoundation/lightwalletd), an own [`zebra`](https://github.com/ycashfoundation/zebra) fork, [`rosetta-bitcoin`](https://github.com/ycashfoundation/rosetta-bitcoin), plus `sapling-crypto-ycash`, `librustzcash`, `WebZjs`, and `zwallet`/`zcash-sync`. Nothing to port to Zero (no shared explorer code), but it is the clearest proof that an active Zcash clone can leave Insight behind for the lightwalletd/zebra stack. Note: several Ycash repos show recent timestamps that are dependency/vendoring churn rather than feature work — do not read them as heavy maintenance.

### 4.2 zcashd deprecation — verified current state

The "deprecated in 2025" line is the announced intent, not a completed retirement. As of this writing zcashd is still shipping releases (v6.20.0 on 2026-06-03). The concrete, verifiable milestone is that since zcashd v6.2.0 operators must set the config flag `i-am-aware-zcashd-will-be-replaced-by-zebrad-and-zallet-in-2025=1` to keep running it — an explicit signal of the migration, not an end date. The official page (z.cash/support/zcashd-deprecation) gives no hard dates for end-of-support, end-of-security-fixes, or removal; RPC compatibility detail is deferred to an external spreadsheet. Bottom line: zcashd is on a managed path off the network toward zebrad + Zallet, but it is not gone, and no firm cutoff date is published. Treat Insight-on-zcashd as functional today and structurally obsolete, not abandoned overnight.

### 4.3 Zebra / zebrad — capability and timeline

[`ZcashFoundation/zebra`](https://github.com/ZcashFoundation/zebra) is a from-scratch Zcash full node in Rust (async/parallel), consensus-compatible with zcashd, co-existing on the network, and faster than zcashd. It is under active release (v5.2.0, 2026-06-18). By mid-2025 Zebra was declared ready for zcashd deprecation, with Zaino and Zallet relying on it. The key compatibility point for an explorer: some zcashd JSON-RPC methods are drop-in on zebrad, some changed, and some are unsupported. An Insight/bitcore-node explorer needs those RPCs plus Insight's extra indexes (addressindex, spentindex, timestampindex), which zebrad does not expose — indexing was deliberately moved out into Zaino. So you cannot point today's bitcore-node at zebrad. That is the structural reason the ecosystem is leaving Insight, not merely the age of the code.

### 4.4 Z3 and Zaino (the replacement indexing stack)

[`ZcashFoundation/z3`](https://github.com/ZcashFoundation/z3) is the "grand unification" stack: Zebra (full node) + Zaino (indexer) + Zallet (wallet) wired together and shipped via Docker Compose, runnable on mainnet, testnet, or local regtest. The architecture: Zebra validates and serves chain data over JSON-RPC; Zaino consumes Zebra's `ReadStateService` for finalized data and exposes both a lightwalletd-compatible CompactTxStreamer gRPC interface and a subset of Zcash JSON-RPCs; Zallet embeds Zaino's indexer libraries and talks to Zebra directly for wallet functions. The goal is to collapse the old zcashd + lightwalletd pair down to zebrad + Zaino, and Z3 ships them as one named, attachable set of services so consumers can depend on the stack by name across networks. Status: active development; Z3 operational across the three network modes.

[`zingolabs/zaino`](https://github.com/zingolabs/zaino) is the indexer itself, in Rust (latest release 0.4.1, 2026-06-18; heavy commit history). It is the component that does what Insight's API does today — it explicitly serves both lightweight clients (wallets) via the CompactTxStreamer gRPC service and full clients (block explorers), over finalized chain data from Zebra plus non-finalized best-chain data. It consolidates indexing that was previously split between lightwalletd and zcashd, and it factors indexing out of Zebra so the node stays lean. For Zero this is the forward-looking template: if Zero ever follows the ecosystem off Insight, a Zaino-class indexer fronting the node (with an explorer UI on top) is the shape it would take. It is not a drop-in for a bitcore-based coin today — it targets the Zcash Rust node, not Equihash forks running zerod — but it is the reference architecture.

### 4.5 Open issues and pending PRs on our and Pirate's Insight repos

Checked all four repos in each org. GitHub's `open_issues_count` counts issues and PRs together, so these are split out explicitly.

Zero (zerocurrencycoin):

- `bitcore-lib-zero`: 0 issues; 1 PR — #4 Dependabot "Bump bcoin 0.15.0 to 1.0.2 in /benchmark" (2020-09-10), stale.
- `bitcore-node-zero`: 0 issues; 1 PR — #3 Dependabot "bump npm 2.15.12 to 6.14.6" (2020-07-16), stale.
- `insight-api-zero`: 0 issues; 3 PRs — #12 "add Crypto 2 Mars" (2022-11-30) and #11 "add zero 2 mars pool" (2022-10-16), both mining-pool metadata from Sil3ntVip3r; #8 Dependabot "bump lodash 2.4.2 to 4.17.19" (2020-07-16).
- `insight-ui-zero`: 2 issues, 0 PRs — #5 "We need help to run insight-ui-zero on 2 different servers" (2024-04-25, support request, looks like spam/help-desk noise) and #4 "Wrong transaction" (2023-07-10, one comment, a possible display/indexing bug worth a look).

Pirate (PirateNetwork):

- `bitcore-lib-pirate`, `bitcore-node-pirate`, `insight-api-pirate`: 0 open issues and 0 open PRs each.
- `insight-ui-pirate`: 0 issues; 1 PR — #1 "ARRRmada provides new donation button" (2023-09-24), a UI/donation tweak.

Summary: nothing security- or consensus-relevant is sitting unmerged in either org. Zero's open PRs are two stale Dependabot bumps plus two mining-pool config adds; the only substantive item is the `insight-ui-zero` "Wrong transaction" issue (#4), which is worth investigating as a real display/indexing symptom. Pirate is essentially clean — the only open item is a cosmetic donation-button PR. So there is no upstream patch queue to harvest from issues/PRs; the value in Pirate is in its merged commit history (tx v5, Sapling handling), not in anything pending.

### 4.6 Visual / UX improvements to pick up, and modern explorers worth looking at

First, the bad news on siblings: there is no visual uplift to be had from any in-family Insight fork. Zero's `insight-ui-zero` is AngularJS ~1.5.8 + Bootstrap ~3.1.1 (both end-of-life), built with bower 1.2.8 + grunt 0.4.2. Every sibling that still runs Insight runs the same dead front end. Pirate's live explorer at [explorer.pirate.black](https://explorer.pirate.black/) is the identical AngularJS Insight UI (templates still use `{{l.name}}`/`insight API v{{version}}` bindings); Pirate's recent `insight-ui-pirate` commits are translations (Indonesian, 2025) and a donation button (2021), not a redesign. TENT/SnowGem ([explorer.snowgem.org](https://explorer.snowgem.org/)) is the same Insight UI again. So "copy a sibling's nicer UI" is not an option — they are all the same 2018-era page.

Horizen is no longer a reference at all. As of July 2025 Horizen migrated off its PoW Zcash-family chain to Base (an EVM Layer 3); ZEN is now an ERC-20 and its explorer is a Blockscout EVM instance ([eon-explorer.horizenlabs.io](https://eon-explorer.horizenlabs.io/), [explorer.horizen.io](https://explorer.horizen.io/)). That is a completely different (EVM/Solidity) data model with nothing to port to a UTXO/Sapling chain. Drop Horizen from the explorer-comparison going forward.

The one genuinely modern, open-source, in-family explorer is Nighthawk's:

- [`nighthawk-apps/zcash-explorer`](https://github.com/nighthawk-apps/zcash-explorer) — Elixir + Phoenix (server-rendered, ~151 commits), the engine behind [mainnet.zcashexplorer.app](https://mainnet.zcashexplorer.app/) (and a testnet instance). This is the closest thing to "what a modern Zcash-family Insight replacement looks like" and the best single source of UI/UX ideas. It is a different stack (Phoenix, not Node/Angular), so it is a redesign reference, not a cherry-pick source, but it is the right thing to imitate.

Concrete UI/UX patterns worth adopting (most observed on zcashexplorer.app, all implementable on the existing Insight UI without a full rewrite):

1. Pool-balance hero stats on the homepage. zcashexplorer.app leads with the shielded-pool total (e.g. Orchard pool ZEC), total blocks, mempool count, and chain size as large cards. Zero already computes `getsupply`/zeronode stats and Sapling data server-side — surfacing a "shielded pool / transparent supply" headline card is mostly a front-end add on data the API already has.
2. Transaction-type badges with clear icons/labels. zcashexplorer.app tags every tx as Coinbase, Shielded (shows 0.0 public), Public/transparent, or Deshielding (z→t). A shielded vs transparent vs coinbase badge is the single highest-value readability improvement for a privacy chain and maps directly onto data Zero's parser already exposes.
3. Dark theme with a single brand accent. The modern look is a dark background plus one accent color (Zcash uses orange #ff7100); Zero would use its own brand color. This is a CSS/theme swap on the existing UI, not a framework change.
4. Relative timestamps ("12 min ago") alongside absolute, and compact recent-blocks / recent-tx tables with height, hash, age, tx count, size, value columns.
5. Operator/utility surface: explicit mempool view, node-status page, broadcast-transaction, and verify-message in a sidebar — Zero's Insight UI already has broadcast/verify, but they are buried; promoting them and adding a node-status page matches the modern layout.
6. Mobile-first responsive layout. Bootstrap 3.1.1 is technically responsive but the 2018 theme is not tuned for phones; a responsive pass is worthwhile regardless of framework.

Two realistic paths, depending on appetite:

- Low effort, high payoff: a theme + component refresh on the existing `insight-ui-zero` — dark theme, brand accent, tx-type badges, pool-balance hero cards, relative timestamps. No framework migration; works against the current API. This is the recommended near-term move and is independent of the Pirate cherry-picks below.
- High effort, future-proof: stand up Nighthawk's Phoenix `zcash-explorer` (or a fork) pointed at zerod. This gets a modern UI for free but is a separate deployment in a new language stack and would need its RPC/index expectations checked against zerod, so it belongs with the longer-term "off Insight" question, not the near-term refresh.

Note: shielded transactions intentionally hide sender/recipient/amount, so no UI improvement changes what is visible for z-address activity — the gain is in clearly labeling what is shielded vs transparent and in surfacing pool-level aggregates, which is exactly what the modern explorers do well.

---

## 5. Options & recommendation for Zero

1. **Best near-term — harvest Pirate's commits.** Pirate runs Zero's identical stack, is
   actively maintained, and is the closest *architectural* match (privacy-default Sapling).
   Their 2024–2026 fixes are the closest thing to a "modern Zero Insight." Low-risk, same
   architecture, no rewrite.
   → Next step: clone `PirateNetwork/{insight-ui,insight-api,bitcore-lib}-pirate` alongside
   ours and produce a portable-commit diff.

2. **Also mine Horizen selectively (one-time).** `HorizenOfficial/*-zen` was the best-maintained Insight
   sibling and likely has the cleanest bug/security fixes in its older library layers.
   **Port selectively** — it carries ZEN-specific concepts (sidechains EON/Gobi,
   secure/super nodes) that don't apply to Zero, and the chain itself has since left PoW
   for Base/EVM, so this is a scavenge, not a relationship.

3. **Medium-term — adopt Komodo's deployment model, WITH CARE.** `zerod` already needs Insight
   indexes (txindex/addressindex/timestampindex/spentindex/zmq). Komodo's
   `komodo-explorers-install` automation + Electrum-for-search is a more maintainable
   deployment pattern than the current manual `bitcore_start.sh > start.out`.
   Caution: **Komodo has many chain-specific nuances and architectural differences (asset-chain
   model, custom komodod dev branch). Do NOT bulk-merge — adopt patterns/ideas, not code,
   and reconcile each piece deliberately.**

4. **Blockbook migration — POSTPONED.** Where the ecosystem is ultimately going (Zcash core
   has effectively deprecated Insight; zerocurrencycoin already has a 2020 `blockbook` fork),
   **but explicitly deferred for now** per direction. Revisit only after the Insight stack is
   modernized via Pirate/Horizen. See the appendix.

### Concrete cherry-pick targets (verified against the local clones)

Ranked by value-to-risk. File paths and commits below were verified by inspecting the local Zero clones and the sibling commit histories on 2026-06-20/21.

High value, do these:

1. Pirate transaction version 5 / Orchard support — **NOT applicable to Zero**; listed here only to close the question. Zero is Sapling-v4 and its chain has no NU5/Orchard/v5 (confirmed: zero references to orchard/nu5/saplingv5/`version >= 5` anywhere in the local source). So there are no v5 transactions for the parser to decode, and porting Pirate's v5 work would add dead code. For reference, Pirate did add it in `bitcore-lib-pirate` `f8c8169` ("Add Transaction Version 5", 2024-10-16) with a follow-up `f6b2de2` ("try/catch", 2024-11-01) and `insight-api-pirate` `131a657` (2024-10-13) — relevant only if Zero ever adopts an NU5-style upgrade on-chain, which is not on the roadmap. Note: the §7 crash #1 (`RangeError` in the tx parser) is a malformed/truncated ZMQ frame, fixed locally by a try/catch (see [InsightFix.md](InsightFix.md)), and has nothing to do with tx version 5.

2. **bn.js security bump (bitcore-lib-zero).** The ProphetAlgorithms side-branch bump from bn.js 2.0.4 to 5.2.3 fixes a ReDoS-class issue and is isolated. Zero's `bitcore-lib-zero` still pins `bn.js =2.0.4`. Safe, self-contained — but track it as its own test-gated change, not bundled with the crash deploy (see [InsightFix.md](InsightFix.md)).

3. `bitcoind.js` spawn/retry handling (bitcore-node-zero). **Resolved locally — not a Pirate cherry-pick.** The original intent was to scan Pirate's `bitcore-node-pirate` for spawn fixes, but their bitcore-node was last touched in 2021 and carries nothing relevant; the `startRetryCount: 60` workaround and the surrounding tip-load retry were reworked directly in our staged `error/bitcoind.js`. The same staged file also bundles the crash #1 rawtx-path guard and the EMFILE fd-leak fix. Full detail in [InsightFix.md](InsightFix.md).

Lower value or caveated:

4. Horizen generic fixes: thinner than expected. Horizen's `bitcore-lib-zen` and `bitcore-node-zen` have not been touched since 2022 — only `insight-api-zen`/`insight-ui-zen` got the 2024 commits, and those are ZEN sidechain/pool config. The one generic-looking item is `bitcore-lib-zen` `453dc40` "Fixed circular dependency" (2021); everything else recent is `zendoo`/certificate/sidechain work specific to ZEN. So Horizen is worth a one-time read of `bitcore-lib-zen` for clean parsing/networks fixes, but it is not a rich source and most of its activity does not apply to Zero.

Already present in Zero, do NOT re-port:

- `saplingblocks.js` and `witness.js` already exist in `insight-api-zero/lib/`. Pirate's 2020 Sapling-block/witness controllers are the same lineage Zero already carries; there is nothing to import there.

Requires manual three-way reconciliation (both sides edited the same files):

- `currency.js` (Zero added CoinGecko handling; upstream rewrote it) and the UI changes. Do not cherry-pick these blindly. (Zero's local `currency.js` has additionally been hardened — see [InsightFix.md](InsightFix.md) crash #4 — which a reconcile must preserve.)

---

## Appendix — The range of explorer alternatives (focus: Blockbook)

### A.1 The field (searched without "insight")

| Explorer | Stack | Multi-coin | Self-host | Fit for Zero |
|---|---|---|---|---|
| **Blockbook (Trezor)** | Go + RocksDB | Yes, many coins including Zcash forks | Yes | **Best long-term**; postponed per direction. zerocurrencycoin already has a 2020 `blockbook` fork. |
| Iquidus Explorer | Node.js + MongoDB | One coin per instance, easily re-skinned | Yes | Proven on Zcash forks (Hush runs it); simpler than Insight, DB-backed; viable fallback. |
| [LBE — Light Block Explorer](https://github.com/hellcatz/lbe-css) (hellcatz, fork of ondrejsika/lbe) | Python + Flask, RPC-only, no DB | Yes, explicitly Zcash and equihash forks (Zclassic, Zdash, Komodo) | Yes, very light | Notable multi-coin equihash explorer; per-coin via RPC creds; needs only `getblock`/`getrawtransaction`/`decoderawtransaction`. Lightweight but lacks rich address indexing. |
| btc-rpc-explorer | Node.js, RPC-only | Bitcoin-likes | Yes | Less Zcash-shielded-aware; weak fit. |
| bitcoincashorg/block-explorer | Node.js, DB-free, RPC | BCH, adaptable | Yes | Adaptable but not Zcash-aware out of the box. |
| Hosted aggregators (Blockchair, Tokenview, blockexplorer.one, chainz.cryptoid, Foundry zcashinfo.com) | SaaS | Yes | No, hosted only | Reference/fallback UIs; not self-hostable. |

Self-hostable multi-coin options are Blockbook (the serious one) and LBE (lightweight, RPC-only, purpose-built to point at any Equihash/Zcash fork by config). Iquidus is one-coin-per-instance but trivially re-skinned. Hosted multi-coin aggregators that already cover Zcash and relatives are Blockchair, Tokenview, blockexplorer.one, and chainz.cryptoid; useful as references but not self-hostable.

### A.2 Blockbook — the main focus

**What it is.** Blockbook is Trezor's block explorer and backend indexer, written in **Go** over **RocksDB**, designed multi-coin from the ground up. It is the serious, actively maintained, self-hostable option and the direction the broader Zcash ecosystem is moving toward (Zcash core has effectively deprecated Insight in its favor).

**Built-in coin coverage relevant to this family.** The cloned `blockbook/configs/coins/` directory ships **100** coin configs, several directly relevant:

| Config | Coin | Relevance |
|---|---|---|
| `zcash.json`, `zcash_testnet.json` | Zcash (ZEC) | The template a `zero.json` would be authored from |
| `firo.json` | Firo | Out-of-family (Bitcoin lineage) but present |
| `flux.json` | Flux (formerly Zelcash) | Equihash sibling |
| `snowgem.json` | SnowGem (now TENT) | Equihash sibling |
| `bitzeny.json`, `bitcore.json` | — | Other precedents |

So Zcash, Flux, SnowGem (TENT), and Firo already have upstream Blockbook templates. **There is no `zero.json`** — a Zero config would be authored from the `zcash.json` template, but the precedent and the address/equihash handling are already present upstream.

**Why it's the best long-term fit.** Active upstream (Trezor itself), multi-coin, DB-backed (RocksDB) so it scales the address indexing that strains the Node-8 Insight heap (the [crash #3 OOM](InsightFix.md) class of problem), and it is where the ecosystem is consolidating.

**Why it's postponed.** Per explicit direction, migration is deferred until the Insight stack is modernized via Pirate/Horizen cherry-picks. It is a new language/runtime (Go/RocksDB) and a separate deployment; the near-term effort is keeping Insight healthy, not replatforming.

**Provenance of the local clone.** `blockbook/` was cloned shallow (`--depth 1`) into the local working copy on 2026-06-20, from `https://github.com/trezor/blockbook` (the canonical Trezor source, **not** a fork). Default branch `master`, HEAD `cfa7374` ("feat(eth): observe alt-mempool tx lifetime and cache depth", 2026-06-19), ~784 stars, actively developed. This is upstream itself. Separately, `zerocurrencycoin/blockbook` exists as a **2020 fork** of this repo (`fork:true`, `parent:trezor/blockbook`, last pushed 2020-12-23) — an abandoned earlier attempt to put Zero on Blockbook; the fresh upstream clone supersedes it.

### A.3 LBE (Light Block Explorer) — the lightweight alternative

Python + Flask, RPC-only, no database. Explicitly oriented at Zcash/equihash forks (its variant lists Zclassic, Zdash, Komodo). Per-coin configuration via RPC credentials; needs only `getblock`/`getrawtransaction`/`decoderawtransaction`. **Lightweight but lacks rich address indexing** — it cannot do the address-history/UTXO queries Insight serves, so it is a reference/fallback, not a replacement.

**Provenance of the local clone.** `lbe-hellcatz/` was cloned shallow (`--depth 1`) on 2026-06-20 from `https://github.com/hellcatz/lbe-css` (the repo `hellcatz/lbe` redirects to). Default branch `master`, HEAD `60d5e73` ("Update lbe.py", 2023-05-19). It is a fork; its root is `ondrejsika/lbe` ("Light Block Explorer — simple block explorer requires only Xcoind RPC interface", last pushed 2020-03-22). Lineage: `ondrejsika/lbe` (generic Xcoind/Bitcoin-RPC explorer, 2020) → `hellcatz/lbe-css` (Zcash/equihash-fork-oriented variant with CSS UI, last touched 2023). Both are tiny single-maintainer projects; treat as a lightweight reference, not a maintained product.
