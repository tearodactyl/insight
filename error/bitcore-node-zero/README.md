Bitcore Node (Zero)
===================

A full node for building applications and services on the Zero (ZER) chain with
Node.js. `bitcore-node-zero` is the orchestrator: it runs as the process named
`bitcore`, loads the Insight API and UI services, and talks to a `zerod` full node
over RPC and ZMQ. `zerod` is the authoritative data layer; the address/spent/
timestamp index RPCs that Insight needs are enabled with flags in `zero.conf`
(see Prerequisites and Configuration below) — no patched daemon fork is required.

> Source-of-record copy. This README is the corrected version staged under
> `error/bitcore-node-zero/` in the Insight docs repo. It replaces stale upstream
> claims (Node v4, ~200 GB / ~8 GB, bitpay binary distribution, a patched
> daemon) with the actuals for the deployed Zero stack.

Lineage: this is the Zero rename-fork of the Zcash Insight stack
([str4d/insight-api-zcash](https://github.com/str4d/insight-api-zcash),
[str4d/insight-ui-zcash](https://github.com/str4d/insight-ui-zcash)), itself
derived from BitPay's [bitcore-node](https://github.com/bitpay/bitcore-node).

## Install

```bash
npm install zerocurrencycoin/bitcore-node-zero
./node_modules/bitcore-node-zero/bin/bitcore-node start
```

This installs `bitcore-node-zero` only. It does **not** download a daemon — you
supply a running `zerod` (see Prerequisites). There is no binary distribution; the
node connects to `zerod` over RPC/ZMQ using the credentials in your config.

## Install bitcore-node-zero with insight-api-zero and insight-ui-zero

Tested on Node.js **v8.17.0** (the last 8.x). Newer Node is not supported by this
dependency tree.

```bash
npm install zerocurrencycoin/bitcore-node-zero
./node_modules/bitcore-node-zero/bin/bitcore-node create mynode
cd mynode
./node_modules/bitcore-node-zero/bin/bitcore-node install zerocurrencycoin/insight-api-zero zerocurrencycoin/insight-ui-zero
```

Set `rpcuser` and `rpcpassword` to match your `zero.conf` (and the RPC port/host)
in the bitcore-node configuration. Then start a standard `zerod` build (release
candidate **4.0.1** is the current target) with the Insight index flags enabled —
see Configuration — and start the node:

```bash
./node_modules/bitcore-node-zero/bin/bitcore-node start
```

Wait for `zerod` to finish syncing. Then open `http://localhost:3001/insight/` —
the Zero Insight home page should load.

## Prerequisites

- GNU/Linux x86_64. Deployed on **Ubuntu 18.04 LTS**, 2 vCPU, 4 GB RAM,
  under 100 GB disk.
- **Node.js v8.17.0** (last 8.x; the dependency tree is frozen circa 2021).
- ZeroMQ *(`libzmq3-dev` on Ubuntu/Debian)*.
- A standard **`zerod`** full node (target release candidate **4.0.1**), built
  normally — no daemon fork. Insight's address queries require the index flags
  below to be enabled in `zero.conf`.

### zerod / zero.conf Insight flags

The address, spent, and timestamp index RPCs that `bitcore-node-zero` calls are
not present in a stock node. On `zerod`, enable them with:

```
insightexplorer=1      # master switch — compiles in the Insight RPCs
txindex=1
addressindex=1
spentindex=1
timestampindex=1
```

These back the RPCs `getrawtransaction`, `getaddresstxids`, `getaddressbalance`,
`getaddressutxos`, `getaddressmempool`, `getspentinfo`, and `getblockhashes`. If
any returns `Method not found`, the corresponding Insight endpoint will fail.

## Configuration

Bitcore includes a Command Line Interface (CLI) for managing, configuring and
interfacing with your node.

```bash
./node_modules/bitcore-node-zero/bin/bitcore-node create -d <zero-data-dir> mynode
cd mynode
./node_modules/bitcore-node-zero/bin/bitcore-node install <service>
```

This creates a directory with configuration files for your node and installs the
necessary dependencies. For more about services, see the
[Service Documentation](docs/services.md).

## Add-on Services

- [Insight API Zero](https://github.com/zerocurrencycoin/insight-api-zero)
- [Insight UI Zero](https://github.com/zerocurrencycoin/insight-ui-zero)

## Documentation

- [Services](docs/services.md)
  - [Bitcoind](docs/services/bitcoind.md) - The RPC/ZMQ interface to `zerod`
  - [Web](docs/services/web.md) - Express application over which services expose their web/API content
- [Development Environment](docs/development.md)
- [Node](docs/node.md) - Details on the node constructor
- [Bus](docs/bus.md) - Overview of the event bus constructor

## Contributing

Please send pull requests for bug fixes, code optimization, and ideas for
improvement.

## License

Code released under [the MIT license](https://github.com/bitpay/bitcore-node/blob/master/LICENSE).

Copyright 2013-2015 BitPay, Inc.

- bitcoin: Copyright (c) 2009-2015 Bitcoin Core Developers (MIT License)
