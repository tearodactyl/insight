# InsightPort — Lineage, Ecosystem Status, Component Versions & Porting

**Zero stack status:** The four `zerocurrencycoin/*-zero` repos are maintained for Zero mainnet. Public explorer: [insight.zeromachine.io](https://insight.zeromachine.io/). See **section 3.1**.

This document covers **where the code came from, what state the in-family Insight
ecosystem is in, what versions run in production, and what is worth porting in**.

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
**bitcoind-rpc** (RPC client to `zerod`).

### Cloned locally
The four direct-dep repos are cloned into the local working copy:
```
bitcore-node-zero/  insight-api-zero/  insight-ui-zero/  bitcore-lib-zero/
```
Each has an `upstream` remote added pointing at `ProphetAlgorithms/<repo>.git`.
The transitive `bitcore-message-zero` is not cloned locally (it exists only in
the deployed install); clone `zerocurrencycoin/bitcore-message-zero` if it needs
review.

The in-family sibling stacks (Pirate, TENT, Horizen) are surveyed below as porting
sources; their local clones live under `ecosystem/`.

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

## 2. Versions & upgrade targets

This is the single home for what runs in production and what each upgrade target
is. Other sections reference it rather than restating versions.

### 2.1 Runtime & platform (deployed)

| Component | Version | Notes |
|---|---|---|
| Node (nvm) | **v8.17.0** | last 8.x; EOL 2019-12-31; the running runtime |
| Node (system) | v8.10.0 | `/usr/bin/node`; unused |
| npm | 6.13.4 | pairs with the nvm Node 8.17.0 |
| OS | Ubuntu 18.04.4 LTS (bionic) | |
| Kernel | Linux 4.15.0-76-generic x86_64 | |
| systemd | 237 | v237 unit gotchas: [InsightBlock.md §4.2](InsightBlock.md#42-systemd-model) |
| nginx | 1.14.0 | TLS terminator / reverse proxy |
| zerod identity | version 3030106, subversion `/Ambrym:3.3.1-beta7(bitcore)/`, protocol 170009 (Sapling) | |

### 2.2 Libraries & build tools (deployed pin → upgrade target)

| Item | Deployed pin | Upgrade target | Notes |
|---|---|---|---|
| bn.js (`bitcore-lib-zero`) | `=2.0.4` | `5.2.3` (upstream side-branch bump) | 2.x→5.x has API breaks — not drop-in; its own test-gated change (§5) |
| elliptic | `=3.0.3` | — | ancient; no target set |
| lodash | `=3.10.1` | — | ancient; no target set |
| grunt | `~0.4.2` | — | UI build tool; rebuild declined (§6.3) |
| bower | `~1.2.8` | — | UI dep fetch; rebuild declined (§6.3) |
| gulp (`bitcore-lib-zero`) | `^3.8.10` | — | lib build; EOL gulp 3 |
| native addons | `zeromq`, `leveldown`, `secp256k1` | rebuild on any Node major | ABI-bound to the runtime |

### 2.3 Node upgrade — target and constraints

Node 8.17 bundles OpenSSL 1.0.2; moving off it is the central upgrade. Targets:

| Target | What it buys | Cost |
|---|---|---|
| Node 10 | OpenSSL 1.1.1 — the [crash #4](InsightFix.md) cert problem resolves at the runtime level | native rebuilds of `zeromq`, `leveldown`, `secp256k1`; `Buffer` API cleanup |
| Node 14 | longer support runway than 10 | same native-rebuild + Buffer work as 10 |

8→10 is the substantive jump; past it is comparatively smooth. The native addons
must be rebuilt against the new ABI, and deprecated `Buffer` constructors cleaned
up. Separately, the AddTrust External CA Root expired 2020-05-30; Node 8's frozen
CA bundle makes outbound TLS to current endpoints fail locally though the remote
certs are valid. The [crash #4 fix](InsightFix.md) handles this at the application
layer (loads the OS CA bundle); a Node 10+ move handles it at the runtime layer.
The two are independent — the app-level fix is correct regardless of any Node move.

Migration is **not started**; v8.17.0 is the deployed runtime. The sequence is
brief and unverified: isolated build env at the candidate Node, rebuild the three
native addons there, `Buffer` sweep, run the lib test suites, parse-replay real
Zero blocks/txs (shielded included) and confirm hashes round-trip identical, then
stage to the host with a held rollback. Any round-trip diff stops the move.

Porting from siblings does not modernize this: Pirate (the primary porting source)
pins the same `bn.js =2.0.4`, `elliptic =3.0.3`, `lodash =3.10.1`, and `node
>=0.12.0` engines. Cherry-picks get chain logic, not a runtime or dependency
upgrade.

---

## 3. Fork lineage & upstream status

### Lineage
```
str4d/*-zcash  →  …  →  ProphetAlgorithms/*  →  zerocurrencycoin/*  (what runs in production)
```
- The **direct parent / real upstream is `ProphetAlgorithms/*`**, not str4d and not
  zerocurrencycoin. ProphetAlgorithms is the last active maintainer of *this* lineage.
- All forks default to branch `master`.

### Divergence from upstream
`zerocurrencycoin` (local) vs `ProphetAlgorithms/master`:

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

### "Recent Prophet push" — explained
`ProphetAlgorithms/bitcore-lib-zero` showed a **2026-02-22** `pushedAt`, looking freshly
maintained. It is **not** human activity:
```
upstream/dependabot/npm_and_yarn/bn.js-5.2.3   2026-02-22  f6c216e  Bump bn.js from 2.0.4 to 5.2.3
```
- A **Dependabot** dependency-bump PR on a *side branch*. `master` is still frozen at 2021-05-05 (`c72c9fe`).
- GitHub's `pushedAt` reflects the newest push across *all* branches → made a dead repo look alive.
- The bump itself is isolated (bn.js 2.0.4 → 5.2.3) — see §2's version table for the upgrade target.

**ProphetAlgorithms upstream:** all four `*-zero` repos on `master` are effectively frozen since **May 2021** (Dependabot side branches excepted).

### 3.1 Zero org repos

| Repo | Role |
|------|------|
| **insight-api-zero** | REST API |
| **bitcore-lib-zero** | Tx/block parsing |
| **bitcore-node-zero** | Orchestrator; RPC/ZMQ to `zerod` |
| **insight-ui-zero** | Web UI |

**Deployment:** [insight.zeromachine.io](https://insight.zeromachine.io/) — **mainnet** Zero Insight. Backend `zerod`: `-experimentalfeatures -insightexplorer`; `-reindex` on first index enable.

**Production pin note:** Table in section **1** lists commits from the last surveyed `mynode` install. Reconcile after `npm install` from GitHub.

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
| Zero (ZER) — ours | [zerocurrencycoin](https://github.com/orgs/zerocurrencycoin/repositories) | `bitcore-lib-zero`, `bitcore-node-zero`, `insight-api-zero`, `insight-ui-zero` | Insight fork | **Active**; mainnet [insight.zeromachine.io](https://insight.zeromachine.io/) |
| upstream of ours | [ProphetAlgorithms](https://github.com/ProphetAlgorithms) | same four `*-zero` repos | Insight fork | Master frozen May 2021; only a Dependabot side-branch since |
| Zclassic (ZCL) — our ancestor | [z-classic](https://github.com/z-classic) | `bitcore-lib-zclassic`, `bitcore-node-zclassic`, `insight-api-zclassic`, `insight-ui-zclassic` | Insight fork | Dead since Feb 2018 (pre-Sapling) |
| Pirate Chain (ARRR) | [PirateNetwork](https://github.com/PirateNetwork) | `bitcore-lib-pirate`, `bitcore-node-pirate`, `insight-api-pirate`, `insight-ui-pirate` | Insight fork | Active; api 2024-10 commit is real tx-parsing work (tx v5) |
| Horizen (ZEN) | [HorizenOfficial](https://github.com/HorizenOfficial) | `bitcore-lib-zen`, `bitcore-node-zen`, `insight-api-zen`, `insight-ui-zen` | Insight fork | Maintained to 2024, but recent commits are ZEN sidechain/pool config; **migrated off PoW to Base/EVM July 2025 — no longer a reference** |
| Komodo + asset chains | [KomodoPlatform](https://github.com/KomodoPlatform) · [DeckerSU](https://github.com/DeckerSU) | Insight plus custom komodod dev branch (txindex/addressindex/timestampindex/spentindex/zmq) plus Electrum for search; `komodo-explorers-install` | Insight + extras | Maintained via install scripts |
| TENT (TENT, formerly SnowGem/XSG) | [TENTOfficial](https://github.com/TENTOfficial) | `tent-insight`, `insight-api-tent`, `insight-ui-tent`, `bitcore-node-tent`, `bitcore-lib-tent` | Insight fork | Genuine Zcash-family Insight fork; frozen 2020-2022 (api last pushed 2022-10); no open issues/PRs |
| Hush (HUSH) | [MyHush](https://github.com/MyHush) | `TheTrunk/explorer-hush` — Iquidus Explorer 1.6.1 (MongoDB) | Different stack (not Insight) | Older/simpler |
| Firo (FIRO, formerly Zcoin/XZC) | [firoorg](https://github.com/firoorg) | No Insight/bitcore; Bitcoin-derived node | Not a Zcash/Equihash fork | Out of family; Bitcoin lineage, FiroPOW (ProgPOW), Spark/Lelantus, not Sapling |

On TENT (formerly SnowGem / XSG): this is a genuine member of the family. The TENTOfficial org carries the full Insight fork (`tent-insight`, `insight-api-tent`, `insight-ui-tent`, `bitcore-node-tent`, `bitcore-lib-tent`), all original (not GitHub forks) repos seeded from the same str4d/Zcash Insight lineage. They are frozen (bitcore repos 2020-12, insight-api last pushed 2022-10) with no open issues or PRs, so it is a portable-in-principle sibling but offers nothing newer than what Pirate already has.

On Firo (formerly Zcoin / XZC): included for completeness, but it is NOT in the Zcash/Equihash family and is not a porting candidate. Firo is a Bitcoin-derived chain — its privacy comes from the Spark protocol (and earlier Lelantus/Sigma/Zerocoin), its Proof-of-Work is FiroPOW (a ProgPOW variant), and it uses LLMQ ChainLocks. It has no Sapling, no Equihash, and no bitcore/Insight repos. Do not treat Firo code as relevant to Zero's Sapling/Equihash stack.

### Maintenance ranking of portable Insight siblings (most to least useful as a source)

1. Pirate (ARRR). `insight-ui-pirate` pushed 2026-06-11, `insight-api-pirate` 2024-10-13, `bitcore-lib-pirate` 2024-11-01. The recent api commit is "add transaction version 5" — genuine tx-parsing/consensus work — plus Sapling handling (`saplingblocks.js`, `witness.js`). Closest architectural match to Zero (privacy-default Sapling). Branches: `master`, `generic-ui`, `saplingroot`. Primary porting source.
2. Horizen (ZEN). `insight-api-zen` 2024-02-29, `insight-ui-zen` 2023-02-09, from a funded org with the most professional codebase. But its distinctive recent commits are ZEN-specific config, and it has since left the PoW chain entirely (below), so it is a one-time selective-scavenging source, not a main line.
3. Zclassic (ZCL). Zero's literal ancestor, but the explorer repos are frozen Feb 2018 (pre-Sapling). Historical reference only.

### Does Horizen have relevant fixes not in Pirate? Largely no.

From the actual recent commit logs:

- Horizen `insight-api-zen` (to 2024-02): recent work is almost entirely ZEN-chain config — "Add Gobi/PreGobi sidechain names", "add Horizen EON as a known sidechain", `sidechains.json` id updates, and `pools.json` mining-pool refreshes. These are EON/Gobi sidechain and pool metadata, not portable bug/security fixes, and they do not apply to Zero (Zero has no sidechains).
- Pirate `insight-api-pirate` (to 2024-10): newest commit is "add transaction version 5" — real tx-parsing/consensus work — plus Sapling handling.

Conclusion: Horizen is the best-engineered sibling and worth scanning for clean generic fixes in `bitcore-lib-zen`/`bitcore-node-zen` (parsing, spawn, networks), but its distinctive recent activity is ZEN-specific. Pirate remains the primary porting source.

### 4.1 Open issues and pending PRs on our and Pirate's Insight repos

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

### 4.2 Visual / UX improvements to pick up

No in-family Insight fork offers a UI to copy. Zero's `insight-ui-zero` is AngularJS ~1.5.8 + Bootstrap ~3.1.1 (both end-of-life), built with bower 1.2.8 + grunt 0.4.2. Every sibling still on Insight runs the same front end: Pirate's live explorer ([explorer.pirate.black](https://explorer.pirate.black/)) is the identical AngularJS Insight UI, its recent `insight-ui-pirate` commits are translations (2025) and a donation button (2021); TENT/SnowGem ([explorer.snowgem.org](https://explorer.snowgem.org/)) is the same UI again. Horizen is out of the comparison: as of July 2025 it migrated off its PoW chain to Base (EVM L3), ZEN is now an ERC-20, and its explorer is a Blockscout EVM instance — a different data model with nothing to port to a UTXO/Sapling chain.

The reference for modern patterns is Nighthawk's [`nighthawk-apps/zcash-explorer`](https://github.com/nighthawk-apps/zcash-explorer) — Elixir + Phoenix (~151 commits), behind [mainnet.zcashexplorer.app](https://mainnet.zcashexplorer.app/). A different stack (Phoenix, not Node/Angular), so a design reference, not a cherry-pick source.

Concrete UI/UX patterns worth adopting (most observed on zcashexplorer.app, all implementable on the existing Insight UI without a full rewrite):

1. Pool-balance hero stats on the homepage. zcashexplorer.app leads with the shielded-pool total (e.g. Orchard pool ZEC), total blocks, mempool count, and chain size as large cards. Zero already computes `getsupply`/zeronode stats and Sapling data server-side — surfacing a "shielded pool / transparent supply" headline card is mostly a front-end add on data the API already has.
2. Transaction-type badges with clear icons/labels. zcashexplorer.app tags every tx as Coinbase, Shielded (shows 0.0 public), Public/transparent, or Deshielding (z→t). A shielded vs transparent vs coinbase badge is the single highest-value readability improvement for a privacy chain and maps directly onto data Zero's parser already exposes.
3. Dark theme with a single brand accent. The modern look is a dark background plus one accent color (Zcash uses orange #ff7100); Zero would use its own brand color. This is a CSS/theme swap on the existing UI, not a framework change.
4. Relative timestamps ("12 min ago") alongside absolute, and compact recent-blocks / recent-tx tables with height, hash, age, tx count, size, value columns.
5. Operator/utility surface: explicit mempool view, node-status page, broadcast-transaction, and verify-message in a sidebar — Zero's Insight UI already has broadcast/verify, but they are buried; promoting them and adding a node-status page matches the modern layout.
6. Mobile-first responsive layout. Bootstrap 3.1.1 is technically responsive but the 2018 theme is not tuned for phones; a responsive pass is worthwhile regardless of framework.

Mapping these against the build posture (§6.3), there are three tiers, not two:

- **No-build (what we actually do): theme + colour via the `custom.css` overlay and
  any change confined to `public/views/**/*.html` templates.** Dark theme, brand
  accent, and template-level relabeling land this way with no grunt rebuild. This is
  the near-term move and is independent of the Pirate cherry-picks below.
- **Needs the declined rebuild: new components driven by `public/src` controllers** —
  tx-type badges, pool-balance hero cards, relative-timestamp directives, compact
  recent-blocks tables. These require regenerating `main.min.js`/`main.min.css`, which
  §6.3 deliberately declines (open-ended regression risk for cosmetic gain). Out of
  scope unless that posture is revisited.
- **High effort: stand up Nighthawk's Phoenix `zcash-explorer`** (or a fork) pointed
  at zerod. A modern UI, but a separate deployment in a new language stack whose
  RPC/index expectations would need checking against zerod — a replatform, not a
  near-term refresh.

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

### Where the parallel projects and upstream are ahead of Zero

What another project or upstream carries that Zero does not — i.e. a different, newer,
or missing implementation worth evaluating. Items Zero already carries identically are
not listed; the point of the evaluation is the divergence. Paths and commits were
verified against the local Zero clones and sibling commit histories on 2026-06-20/21.

- **bn.js (upstream has a fix Zero lacks).** Zero's `bitcore-lib-zero` pins `bn.js =2.0.4`; upstream `5.2.3` carries a fix Zero's pin predates. A 2.x→5.x jump has API breaks — not drop-in; track it as its own test-gated change, not bundled with the crash deploy. Validation approach and rationale: §2 version table.
- **Horizen (evaluated, nothing portable).** `bitcore-lib-zen`/`bitcore-node-zen` untouched since 2022; the 2024 commits are all `insight-*-zen` ZEN sidechain/pool config (`zendoo`/certificate/sidechain-specific). The one generic-looking item, `bitcore-lib-zen` `453dc40` "Fixed circular dependency" (2021), is N/A to Zero (Zero never had the `Block↔BlockHeader` cycle). Reviewed and closed — no portable change.
- **`currency.js` (diverged — needs three-way reconcile).** Zero added CoinGecko handling; upstream rewrote the same file; both sides edited it. Do not cherry-pick blindly — Zero's local `currency.js` is additionally hardened (InsightFix.md crash #4), which a reconcile must preserve.
- **Pirate transaction version 5 / Orchard (sibling has it; not relevant to Zero's chain).** Pirate carries v5/Orchard; Zero is Sapling-v4 with no NU5/Orchard activated, so there are no v5 transactions to decode and nothing to port — unless Zero ever activates an NU5-style upgrade on-chain, at which point this becomes a live target.

---

## 6. Ecosystem build toolchain & Node-pinning status

Verified 2026-06-23 against the local clones under
`$INSIGHT/ecosystem/{Pirate,TENT,Zen}/` (where `INSIGHT` is the local Insight repo
root) — the full
four/five-repo Insight stacks for Pirate (ARRR), TENT (TENT/SnowGem), and Horizen
(ZEN). The takeaway: **no sibling has modernized the toolchain, and none pins
Node.** Porting buys chain logic, not a build-system or runtime upgrade — this
section is the evidence behind that claim in §2 and §4.

### 6.1 Build tools per repo (the whole ecosystem)

The toolchain is uniform by repo *role*, not by coin. Each role uses the same
build tool across all three families:

| Repo role | Build tool | Version (all families) | Notes |
|---|---|---|---|
| `bitcore-lib-*` | gulp | `^3.8.10` | gulp 3 (EOL); compiles lib primitives |
| `bitcore-node-*` | none | — | mocha/jshint only; no asset build |
| `insight-api-*` | none | — | mocha only; no asset build |
| `insight-ui-*` | grunt + bower | `grunt ~0.4.2`, bower per below | the only repo that needs grunt **and** bower |

**bower pin — the one ecosystem deviation:**

| Repo | bower | grunt |
|---|---|---|
| `insight-ui-pirate` | `~1.2.8` | `~0.4.2` |
| `insight-ui-tent` | `~1.2.8` | `~0.4.2` |
| `insight-ui-zen` | **`^1.8.8`** | `~0.4.2` |
| `insight-ui-zero` (ours) | `~1.2.8` | `~0.4.2` |

Horizen's `insight-ui-zen` is the **only** repo in the entire sweep that bumped
bower (to `^1.8.8`, vs everyone else's `~1.2.8`). That is the single toolchain
modernization any sibling made, and it is small. Everything else — grunt 0.4.2,
gulp 3.8, AngularJS 1.5 / Bootstrap 3.1 — is identical 2018-era EOL tooling
across Zero and all three siblings.

### 6.2 Node pinning & engines — there is none

| Signal | Finding across all 13 ecosystem repos |
|---|---|
| `.nvmrc` / `.node-version` / `.tool-versions` | **None.** Zero pin files anywhere — same as our own four repos. |
| `package.json` `engines.node` | Only `insight-api-{pirate,tent,zen}` declare anything, and it is identically `>=0.12.0` — a 2016 BitPay inheritance, not a real floor. All other repos: absent. |
| README Node prose | Every `bitcore-node-*` README carries the same **stale** 2016 text: *"Prerequisites: Node.js v0.10, v0.12 or v4."* None updated it to the Node-8 reality they actually run on. |

So there is no pinning discipline to copy and no sibling that documents a
known-good Node version. Our own [InsightBlock.md §4.0](InsightBlock.md#40-installing-from-scratch)
("Node runtime: `nvm install 8.17.0`") is the **only** authoritative Node-version
statement in the whole family — the siblings leave it implicit.

### 6.3 Did Horizen's changes require a grunt/bower rebuild? Yes — verified.

Question raised: were Horizen's recent `insight-ui-zen` changes source-level
(needing the grunt/bower toolchain to take effect) or only template/HTML edits?
Answer from the commit history (`ecosystem/Zen/insight-ui-zen`, HEAD `df08994`
2023-02-09): **they ran grunt, and committed its output.** Horizen's workflow:

1. Edit source — `public/src/js/controllers/*.js`, `public/src/css/common.css`, `po/*.po`.
2. Run `grunt compile` — regenerating the served bundle: `public/js/{angularjs-all,main,vendors}.min.js`, `public/css/main.min.css`, `public/src/js/translations.js`.
3. Commit the regenerated `*.min.js` / `*.min.css` artifacts, sometimes as a dedicated commit.

The evidence: commit `51feef3` is titled literally **"grunt compile"** and
contains *only* regenerated `public/js/*.min.js`; `ce51aa8` "Regenerate assets"
rebuilt `main.min.css` + the three `min.js` bundles. Feature commit `1b69eaf`
touched `public/src/js/controllers/transactions.js` (grunt source) and the
rebuilt `main.min.js` followed.

**Implication for the [§4.2](#42-visual--ux-improvements-to-pick-up)
UI refresh — the build constraint is real, and we deliberately decline to cross it.**

The UI serves the **built** `public/js/*.min.js` and `public/css/main.min.css`,
not the `public/src/` tree. Any edit under `public/src/{js,css}` only reaches the
browser after `grunt compile` regenerates those bundles (and bower must be present
to populate `public/lib` so grunt can concatenate `vendors.min.js`). Running that
2018 toolchain — grunt 0.4.2 / bower 1.2.8 on Node 8.17.0 — to regenerate
`main.min.js`/`main.min.css` is **not something we attempt**: the expected cost is
high and, worse, a rebuild risks an unbounded set of hard-to-detect regressions in
the served bundle (silent reordering, dropped concatenation, dependency-resolution
drift) that would be very difficult to catch against a 2018 AngularJS/Bootstrap
front end. The downside is open-ended and the upside is cosmetic, so we hold the
existing built bundle as-is.

#### Served paths vs source (canonical)

The browser loads what `index.html` references — not the `public/src/` tree.
Bitcore serves `insight-ui-zero/public/` as static files under `/insight/`; there is
no dev-server transpile step in production.

| Path under `insight-ui-zero/public/` | Browser loads? | Grunt rebuild? | How deployed UI work ships |
|---|---|---|---|
| `views/**/*.html`, `index.html` | yes (runtime Angular templates) | **no** | edit file; reference copies in docs `samples/` |
| `css/custom.css`, `img/**` | yes | **no** | edit file; theme overlays `main.min.css` |
| `js/main.min.js`, `js/*.min.js`, `css/main.min.css` | yes (`index.html` script/link tags) | **normally declined** — hold upstream bundle | hand-patch min file **or** edit `public/src/` then `grunt compile` (§6.4) |
| `public/src/js/**`, `public/src/css/**` | **no** (source only) | yes — output must land in `js/*.min.js` / `main.min.css` | not served until compiled or mirrored by a min-file hand-patch |

#### How `index.html` wires the browser

At the bottom of `index.html` (and the matching live file), scripts load in fixed order:

1. `js/vendors.min.js` — third-party libs from `public/lib/` (bower output, concatenated by grunt)
2. `js/angularjs-all.min.js` — Angular stack slice
3. `js/main.min.js` — app module: controllers, services, directives, routing

Styles: `css/main.min.css` (grunt-built from `public/src/css/`), then **`css/custom.css`**
(one extra `<link>` added for Zero — not part of the upstream bundle).

Nothing under `public/src/` appears in those tags. Editing `public/src/js/controllers/currency.js`
on disk does **nothing** in a user's browser until its logic is copied into `main.min.js`
(by grunt or by hand).

Templates under `public/views/` are different: Angular loads them over HTTP when a route or
`ng-include` resolves (e.g. `views/includes/connection.html`). They are plain HTML on disk —
no concatenation step — which is why the zerod offline banner shipped without touching grunt.

#### Why templates and `custom.css` need no build

- **Templates** — fetched at runtime; `$templateCache` and `ng-include` read the file the
  server already exposes. Change the HTML, deploy, hard-reload (and purge CDN if applicable).
- **`custom.css`** — additive stylesheet loaded *after* `main.min.css`. Overrides use the same
  class names the bundle already defines; `!important` is sometimes needed where upstream rules
  are specific. **`main.min.css` is never hand-edited** — re-tinting stays in `custom.css`.
- **Images / favicons** — static files; same deploy path as templates.

**Without editing `main.min.js` (or other `*.min.*` bundles):** templates, `index.html`,
`custom.css`, and static images. That covers every routine UI change shipped so far (connection
banner, theme, favicons, status copy). Footer *labels* in `currency.html` can change;
**controller logic** (e.g. what value `currency.factor` holds) lives only in `main.min.js`.

#### When you must touch `main.min.js`

Use this decision guide before editing:

| You want to change… | Edit | Grunt? |
|---|---|---|
| Wording, layout, visibility in a `.html` view | `public/views/…` | no |
| Colours, spacing, navbar/search chrome | `public/css/custom.css` | no |
| Favicon, icons, static art | `public/img/…` | no |
| `$scope` / `$rootScope` behaviour, services, routing, filters | `public/js/main.min.js` (or `public/src/` + rebuild) | hand-patch: no; full rebuild: yes (declined) |
| Upstream LESS/CSS in the built theme | `public/src/css/` then rebuild | yes (declined) — prefer `custom.css` instead |

**Templates bind to scope names defined in `main.min.js`** (e.g. `currency.factor`, `sync.status`).
Changing the footer *text* is template work; changing what `factor` *is* when ZER is selected is
controller work and requires `main.min.js` (currency factor footer — postponed; see
InsightFix.md **Consider**).

#### Hand-patching `main.min.js` vs `grunt compile`

Edits under `public/src/` do **not** reach the browser by themselves. Two ways to change
JS behaviour:

1. **`grunt compile`** after editing `public/src/` — regenerates `main.min.js` and
   related bundles from the full source tree. Full 2018 toolchain; **declined** for routine
   work (regression risk, §6.3 opening). Horizen's workflow: edit src, run grunt, commit the
   new `*.min.js` artifacts.
2. **Hand-patch `public/js/main.min.js`** — edit the served bundle directly (typically a
   unique find/replace inside a minified controller). **No grunt run**; the browser loads
   the patched file on next deploy. This is the practical hotfix path when rebuild is declined.

**Hand-patch workflow:**

- Locate the minified block with `grep` (must be a **unique** string — one match only).
- Apply the smallest change that mirrors what you would put in `public/src/…`.
- Commit **both** the min patch and the readable `public/src/` file when possible, so a
  future rebuild does not silently drop the fix.
- Smoke-test in browser: currency footer, routing, search — minified edits are easy to break
  with a missing comma or truncated identifier.
- No `node --check` on the bundle; syntax errors surface only at runtime.

**Misreadings to avoid:**

- *"Editing `public/src` affects the browser"* — **false** unless you also update `main.min.js`
  or run `grunt compile`.
- *"No grunt means no JS changes"* — **false** — hand-patching `main.min.js` is a JS change
  without grunt.
- *"Templates can fix controller bugs"* — **false** when the bug is the value bound to scope
  (factor regression), not the label around it.

So "no grunt rebuild" is true for templates/CSS/images. For controller fixes, the
alternative to grunt is **patch `main.min.js` on disk**, not skip the bundle.

#### What we ship on the no-build path

Routine deployed UI work uses only:

- **`public/views/**/*.html`** — loaded at runtime (e.g. `connection.html` offline banner).
- **`custom.css`** — layered after `main.min.css`.

Deeper refresh needing recompiled `public/src/{js,css}` (new directives, table columns driven
by controller refactors, upstream CSS recompile) is **out of scope** unless §6.4 is invoked.
Example of controller work needing a min patch: currency `factor` display (InsightFix.md
**Consider** — not shipped).

Controller logic changes require `main.min.js` — hand-patch or declined full rebuild.

### 6.4 Running the 2018 toolchain — only if the rebuild is ever revisited

We do **not** run this build today (§6.3); this section exists solely so that, if a
future decision reverses that posture, the known-good environments are already
identified rather than re-discovered. Nothing below is part of the current workflow.

#### Rebuild prerequisites (not just grunt and bower)

A fresh `insight-ui-zero` clone is not build-ready. Before `grunt compile`:

| Step | Why |
|---|---|
| **Node.js v8.17.0** | Last 8.x; only supported runtime for this dependency tree (InsightBlock.md §4.0). Modern Node (e.g. v25) fails on native/gyp deps; Apple Silicon needs Docker or an x86/Node-8 environment. |
| **`npm install`** | Installs grunt, concat/minify plugins, and other devDependencies into `node_modules/` (absent in a bare clone). |
| **`bower install`** | Populates `public/lib/` with vendored Angular, Bootstrap, etc. A sparse clone may only have `zeroclipboard`; grunt cannot build `vendors.min.js` without the full bower tree. |
| **`grunt compile`** | Regenerates `public/js/{angularjs-all,main,vendors}.min.js`, `public/css/main.min.css`, and `public/src/js/translations.js`. Default `grunt` also watches; one-shot build uses `grunt compile`. |

Template/CSS-only deploys need **none** of the above. Hand-patching `main.min.js` also
needs none — only a text edit and deploy.

#### What `grunt compile` consumes and produces

Rough data flow (upstream `Gruntfile.js` in `insight-ui-zero`):

```
bower install  -->  public/lib/          (Angular, Bootstrap, …)
public/src/js/   -->  grunt concat/uglify -->  public/js/main.min.js
public/src/css/  -->  grunt less/minify  -->  public/css/main.min.css
public/lib/      -->  grunt concat       -->  public/js/vendors.min.js
po/*.po          -->  grunt gettext      -->  public/src/js/translations.js  (also folded into main)
```

If `bower install` was skipped, grunt typically fails mid-task with missing files under
`public/lib/`. If `npm install` was skipped, `grunt` itself is not on PATH / not in
`node_modules/.bin/`. Both must succeed on **Node 8.17.0** before trusting output.

**After a rebuild (if ever run):** diff the three `public/js/*.min.js` and `main.min.css`
against the previous commit — expect large hunks even for small src edits. Smoke-test
routing, search, currency pulldown, and block/tx pages before promoting to production.
A silent concat order change can break Angular DI without a compile error.

#### Build environments

Local system Node is modern (e.g. v25.x); the toolchain needs **Node 8.17.0**,
and `npm install` of the native/gyp-heavy deps fails on Apple Silicon under
modern Node. Two viable build environments:

1. **Host-side (HOST) — path of least resistance.** The live host already has the
   full source tree plus a working nvm **Node 8.17.0** — it *is* the documented,
   known-good build environment. Run `npm install && bower install && grunt
   compile` there under that Node. Subject to the standing rule: **no host write
   without explicit go-ahead**, and the user controls service stop/start.
2. **Off-host (local Mac) — Docker `node:8.17.0`.** The official prebuilt image
   avoids compiling Node 8 on ARM. `docker run -v $PWD:/app -w /app node:8.17.0
   sh -c 'npm install && bower install --allow-root && grunt compile'`. Robust
   because it sidesteps both the ARM/Node-8 native-build failure and the missing
   local `node_modules`.

Per-repo Node selection without changing the system default: drop an `.nvmrc`
(`8.17.0`) in the repo and `nvm use`, or run one-off via `nvm exec 8.17.0 <cmd>`.
No sibling does this (§6.2); it would be a Zero-local convenience, not a port.
