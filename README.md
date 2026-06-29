# Zero (ZER) Insight Block Explorer

Operations and engineering documentation for the Zero Insight block explorer — the
public block explorer for the Zero (ZER) chain, and the node it runs against.

## Introduction

The explorer is one Node process (`bitcore`) fronting one Zero full node (`zerod`),
behind nginx. Four coupled npm packages make up the explorer —
`bitcore-lib-zero`, `bitcore-node-zero`, `insight-api-zero`, `insight-ui-zero`.
`bitcore-node-zero` is the orchestrator and runs as the process named `bitcore`; it
loads the API, the AngularJS UI, and the `bitcoind` service that talks to `zerod`
over RPC and ZMQ.

```
client ──TLS──> nginx :443 ──cleartext──> bitcore :3001 ──RPC :23811──> zerod
                                                          └──ZMQ :28332──┘
```

The Zero packages are a rename-fork of str4d's Zcash Insight; `zerod` is a
Zcash/bitcoin-derived full node and the authoritative data layer. The stack runs on
Node v8.17.0 (the last 8.x, EOL 2019-12-31) against a dependency tree frozen circa
2021. The operating posture is to maintain and harden the stack in place rather than
upgrade the runtime; the details and the reasoning are in
[InsightBlock.md](InsightBlock.md).

This documentation assumes an expert reader: a senior Linux administrator and
software engineer. It covers running the explorer, the crashes seen in production
and their fixes, the fork's lineage and version walls, and host maintenance.

The current state of the work: the production crash fixes are deployed (the backend
`.js` hardening plus the "zcashd"→"zerod" banner), and a subsequent round of UI,
theme, and image tuning has been applied to the front end. Both are covered below.

## Project status

| Item | Status |
|------|--------|
| **Public explorer** | [https://insight.zeromachine.io/](https://insight.zeromachine.io/) — **mainnet** Zero Insight |
| **Stack repos** | `insight-ui-zero`, `insight-api-zero`, `bitcore-lib-zero`, `bitcore-node-zero` |
| **Node backend** | `zerod` with `-experimentalfeatures`, `-insightexplorer`, `-txindex`; `-reindex` on first index enable |
| **Indexer scope** | Transparent **t-address** search via daemon addressindex RPCs; shielded z-addrs not indexed chain-wide |
| **Public docs** | Zero **README**, **BUILD_ZERO**, **ZERO_COIN** (Block explorer sections) |

## Documentation map

The maintained, definitive documentation set is this `README.md`, the `Insight*.md`
references, and the two artifact directories [`error/`](error/) and
[`config/`](config/).

| Document | Holds |
|---|---|
| [README.md](README.md) | This overview: the introduction, the documentation map, and the role-based entry points. |
| [InsightBlock.md](InsightBlock.md) | The central reference: what the explorer is, where it lives on disk, and how to operate it — install, launch, shutdown, recovery, the systemd model, log control, nginx. Plus Appendix A (developer internals), Appendix B (integrator API), Appendix C (suggestions, unimplemented). |
| [InsightFix.md](InsightFix.md) | The four production crash signatures, the `.tail` captures, and the deployed hardening — five backend `.js` files plus the UI "zcashd"→"zerod" banner fix (one template, `translate` directive removed); the fixes are in the package source, with patched reference copies under [`error/`](error/). Includes monitoring, sizing, and message-test procedures. The later UI/theme/image tuning rides on top of these fixes. |
| [InsightPort.md](InsightPort.md) | Fork lineage, upstream/ecosystem status, component/module versions, upgrade walls, the ecosystem build-toolchain & Node-pinning survey (grunt/bower/gulp, the grunt-rebuild wall), porting and strengthening. |
| [`error/`](error/) | Patched reference copies of the hardened files: the five backend `.js` files (flat) plus the one UI banner template (`connection.html`) in a path-preserving `insight-ui-zero/public/…` subtree. The fixes ship in the package source; these copies are a convenient catalogued reference. See InsightFix.md. |
| [`config/`](config/) | The deployed files verbatim: `zerod.service`, `bitcore.service`, `bitcore-node.json` (+`.spawn.bak`), `bitcore_start.sh`, `zero.conf`, `nginx-default`, `journald.conf`, `logrotate-bitcore`. |

## Start here, by role

**Administrator** — running `zerod` and `bitcore` on the host.

- Install from scratch: [InsightBlock.md §4.0](InsightBlock.md#40-installing-from-scratch)
- Day-to-day operation (launch, control, reboot): [InsightBlock.md §4](InsightBlock.md#4-operations)
- Recovery (crashes, locks, hangs, rollback, disk-full): [InsightBlock.md §5](InsightBlock.md#5-recovery)
- The connect-vs-spawn model and the systemd coupling: [InsightBlock.md §3](InsightBlock.md#3-operating-modes--connect-vs-spawn)
- Crash signatures and their fixes: [InsightFix.md](InsightFix.md)
- Deployed file reference: [`config/`](config/)

**Developer** — working on the explorer code.

- Developer internals (ZMQ multiplexing, connect/spawn in code, the tip loader, crash catalog): [InsightBlock.md Appendix A](InsightBlock.md#appendix-a--developer-internals)
- Deployed fixes and the crash analysis: [InsightFix.md](InsightFix.md) and [`error/`](error/)
- Fork lineage, versions, and upgrade walls: [InsightPort.md](InsightPort.md)

**Integrator** — building an app or wallet against the explorer API.

- The route prefix and why it is `/insight-api-zero`: [InsightBlock.md Appendix B](InsightBlock.md#appendix-b--integrator-api)
- Endpoints: [InsightBlock.md Appendix B.2](InsightBlock.md#b2-endpoints)

---

## UI round 2 (mainnet polish)

Static HTML/CSS changes in **`insight-ui-zero`** (no **`grunt`** rebuild). Staged copies also under [`samples/`](samples/) for review before promoting into the package repo.

| File | Change |
| ---- | ------ |
| `public/index.html` | Mainnet `<title>` and meta **first** (no pre-Angular "Testnet Zero Insight" default). |
| `public/views/status.html` | **Network** shows **`mainnet`** when API returns **`livenet`**. **Warnings** row (was Info Errors) shows **`info.errors`** only when set and not a partition-check rate message. |

### Deploy on toru

Connect mode: only **`bitcore`** restarts for backend **`.js`**; these files are **`express.static`** and need **no** `systemctl` restart. Copy into the live tree, then verify through nginx/CDN.

```sh
# From laptop (paths match toru layout)
UI=/home/ubuntu/zero/mynode/node_modules/insight-ui-zero/public
scp insight-ui-zero/public/index.html \
    insight-ui-zero/public/views/status.html \
    toru:$UI/
scp insight-ui-zero/public/views/status.html toru:$UI/views/

# Served-bytes checks (after Cloudflare purge if tab title still stale)
curl -sL https://insight.zeromachine.io/insight/views/status.html | grep -E 'mainnet|info.errors'
curl -sL https://insight.zeromachine.io/insight/ | grep -o '<title[^>]*>[^<]*</title>' | head -1
```

**Pass criteria:** status template contains **`livenet ? 'mainnet'`**; first static `<title>` is **Zero Insight**; **Warnings** row hidden when **`getinfo.errors`** is empty or a partition-check message (`blocks received in the last`).

Procedure detail: [InsightFix.md §4.3](InsightFix.md) (cache flush), [InsightBlock.md §5.7](InsightBlock.md#57-deploying-updated-explorer-packages) (package **`npm install`** path when pulling from GitHub instead of hot-copy).

### Git commit identity

Insight stack commits should author as **`tearodactyl <tearodactylus@gmail.com>`**.

Scripts live under **`~/Work/ZK/gits/`** (shared across clones, not in this docs repo):

```sh
# Once per clone (local only, does not change global git config)
bash ~/Work/ZK/gits/git-author-setup.sh \
  ~/Work/ZK/ZKs/insight/insight-ui-zero \
  ~/Work/ZK/ZKs/insight/insight-api-zero \
  ~/Work/ZK/ZKs/insight/bitcore-node-zero \
  ~/Work/ZK/ZKs/insight/bitcore-lib-zero \
  ~/Work/ZK/ZKs/insight

# Optional hook in each code repo
cp ~/Work/ZK/gits/pre-commit-check-author insight-ui-zero/.git/hooks/pre-commit
chmod +x insight-ui-zero/.git/hooks/pre-commit
```

Older pushes under a personal email are unchanged unless history is rewritten (force-push to **`zerocurrencycoin/*`** only if org policy allows it).
