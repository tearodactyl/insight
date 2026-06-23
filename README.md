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
2021, so the operating posture is **harden in place**, not upgrade — the details and
the reasoning are in [InsightBlock.md](InsightBlock.md).

This documentation assumes an expert reader: a senior Linux administrator and
software engineer. It covers running the explorer, the crashes seen in production
and their fixes, the fork's lineage and version walls, and host maintenance.

## Documentation map

The maintained, definitive documentation set is this `README.md`, the `Insight*.md`
references, and the two artifact directories [`error/`](error/) and
[`config/`](config/).

| Document | Holds |
|---|---|
| [README.md](README.md) | This overview: the introduction, the documentation map, and the role-based entry points. |
| [InsightBlock.md](InsightBlock.md) | The central reference: what the explorer is, where it lives on disk, and how to operate it — install, launch, shutdown, recovery, the systemd model, log control, nginx. Plus Appendix A (developer internals), Appendix B (integrator API), Appendix C (suggestions, unimplemented). |
| [InsightFix.md](InsightFix.md) | The four production crash signatures, the `.tail` captures, and the hardening **deployed 2026-06-23** — five backend `.js` files plus the UI "zcashd"→"zerod" banner fix (one template, `translate` directive removed); source of record in [`error/`](error/). Includes monitoring, sizing, and message-test procedures. |
| [InsightPort.md](InsightPort.md) | Fork lineage, upstream/ecosystem status, component/module versions, upgrade walls, porting and strengthening. |
| [`error/`](error/) | The deployed fix artifacts, source of record: the five hardened backend `.js` files (flat) plus the one UI banner template (`connection.html`) in a path-preserving `insight-ui-zero/public/…` subtree. Each backend file is `node --check`-clean and diffed against the deployed original. Catalogued in InsightFix.md. |
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
