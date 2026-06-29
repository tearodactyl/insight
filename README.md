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
`.js` hardening plus the "zcashd"→"zerod" banner), and a UI/theme round (mainnet
labels, `custom.css`, favicons, status-page polish) is live in production. Staged copies
under [`samples/`](samples/) match the deployed tree byte-for-byte; see
[`samples/README.md`](samples/README.md) for the file list and for experiments that
were reverted (Live banner, `logo.svg`, coloured sync bar, etc.).

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
| [`error/`](error/) | Patched reference copies of the hardened backend `.js` files (flat) plus `insight-ui-zero/public/views/includes/connection.html`. `error/currency.js` includes the crash #4 CA fix, CoinGecko User-Agent, and the `binance` JSON alias. See InsightFix.md and [`samples/README.md`](samples/README.md). |
| [`samples/`](samples/) | Deployed UI mirror: production `insight-ui-zero/public/` files (HTML/CSS/icons). Authoritative list in [`samples/README.md`](samples/README.md). |
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

## Deployed UI and API (production)

Full file list, checksums, and reverted experiments: [`samples/README.md`](samples/README.md).

| Area | Deployed |
| ---- | -------- |
| **UI** (`samples/` = production) | Mainnet title/meta, `custom.css`, PNG favicons, About links, mainnet/**Warnings** on status page, hardcoded genesis dates, §4a zerod banner, text **Zero** header, currency factor row |
| **UI not deployed** | Live green banner, `logo.svg`, traffic-light labels, coloured sync bar, search echo/extra spinner, `/sync` timestamp fields |
| **API** | `insight-api-zero/lib/currency.js`: crash #4 CA fix, User-Agent, `binance: self.usd` (mirror in `error/currency.js`) |

Static HTML/CSS: copy into `node_modules/insight-ui-zero/public/`, no bitcore restart; purge Cloudflare if stale. Backend `.js`: copy then restart bitcore.

```sh
# Served-bytes spot checks
curl -sL https://insight.zeromachine.io/insight/views/status.html | grep -E 'mainnet|blocks received in the last'
curl -sL https://insight.zeromachine.io/insight-api-zero/currency | python3 -m json.tool | grep binance
```

Procedure: [InsightFix.md](InsightFix.md) (§4a banner, cache flush), [InsightBlock.md §5.7](InsightBlock.md#57-deploying-updated-explorer-packages) (package update path).
