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

Backend crash hardening and the UI zerod connection banner are documented in
[InsightFix.md](InsightFix.md). UI reference files under [`samples/`](samples/) and
backend reference files under [`error/`](error/) are described in the documentation
map below.

## Project status

| Item | Status |
|------|--------|
| **Public explorer** | [https://insight.zeromachine.io/](https://insight.zeromachine.io/) — **mainnet** Zero Insight |
| **Stack repos** | `insight-ui-zero`, `insight-api-zero`, `bitcore-lib-zero`, `bitcore-node-zero` |
| **Node backend** | `zerod` with `-experimentalfeatures`, `-insightexplorer`, `-txindex`; `-reindex` on first index enable |
| **Indexer scope** | Transparent **t-address** search via daemon addressindex RPCs; shielded z-addrs not indexed chain-wide |
| **Public docs** | Zero **README**, **BUILD_ZERO**, **ZERO_COIN** (Block explorer sections) |

## Documentation map

The maintained documentation set is this `README.md`, the `Insight*.md` references,
and three artifact directories.

| Document / path | Holds |
|---|---|
| [README.md](README.md) | This overview, documentation map, role-based entry points |
| [InsightBlock.md](InsightBlock.md) | Operations reference: install, launch, recovery, systemd, nginx, integrator API appendices |
| [InsightFix.md](InsightFix.md) | Production crash signatures, mitigations, deployed hardening, monitoring |
| [InsightPort.md](InsightPort.md) | Fork lineage, versions, upgrade walls, build-toolchain survey |
| [`config/`](config/) | Example configuration for the host environment that serves the explorer (`zerod`, `bitcore`, nginx, journald, and related units) |
| [`error/`](error/) | Reference copies of modified backend `.js` files (and selected UI templates where noted in InsightFix) |
| [`samples/`](samples/) | Reference copies of modified UI files: HTML, CSS, and images under `insight-ui-zero/public/` |

Package source for the four explorer repos lives in separate `zerocurrencycoin/*-zero`
repositories. Nested clones may exist in a maintainer checkout but are not part of this
documentation tree.

## Start here, by role

**Administrator** — running `zerod` and `bitcore` on the host.

- Install from scratch: [InsightBlock.md §4.0](InsightBlock.md#40-installing-from-scratch)
- Day-to-day operation (launch, control, reboot): [InsightBlock.md §4](InsightBlock.md#4-operations)
- Recovery (crashes, locks, hangs, rollback, disk-full): [InsightBlock.md §5](InsightBlock.md#5-recovery)
- The connect-vs-spawn model and the systemd coupling: [InsightBlock.md §3](InsightBlock.md#3-operating-modes--connect-vs-spawn)
- Crash signatures and their fixes: [InsightFix.md](InsightFix.md)
- Example host configuration: [`config/`](config/)

**Developer** — working on the explorer code.

- Developer internals (ZMQ multiplexing, connect/spawn in code, the tip loader, crash catalog): [InsightBlock.md Appendix A](InsightBlock.md#appendix-a--developer-internals)
- Deployed fixes and the crash analysis: [InsightFix.md](InsightFix.md) and [`error/`](error/)
- UI reference files: [`samples/README.md`](samples/README.md)
- Fork lineage, versions, and upgrade walls: [InsightPort.md](InsightPort.md)

**Integrator** — building an app or wallet against the explorer API.

- The route prefix and why it is `/insight-api-zero`: [InsightBlock.md Appendix B](InsightBlock.md#appendix-b--integrator-api)
- Endpoints: [InsightBlock.md Appendix B.2](InsightBlock.md#b2-endpoints)
