# Zero (ZER) Insight Block Explorer — Operations Reference

> The how-to-run-it reference for the Zero Insight explorer.
> Audience: the server administrator running `zerod` and `bitcore`. Expert reader
> assumed (senior Linux sysadmin + software engineer).
>
> Part of the Zero Insight explorer docs — see [README.md](README.md) for the
> project overview, the documentation map, and role-based entry points (Admin,
> Developer, Integrator).

---

## 1. What it is

The Zero Insight explorer is one Node process (`bitcore`) fronting one full node
(`zerod`), behind nginx; the architecture and lineage are in
[README.md](README.md). This section pins down the three runtime components and
their identities — the rest of the reference builds on them.

```
client ──TLS──> nginx :443 ──cleartext──> bitcore :3001 ──RPC :23811──> zerod
                                                          └──ZMQ :28332──┘
```

- **`zerod`** — the Zero full node, a Zcash/bitcoin-derived daemon and the
  authoritative data layer. It owns the blockchain datadir, serves RPC, and
  publishes ZMQ tx/block notifications. Identity: version `3030106`, subversion
  `/Ambrym:3.3.1-beta7(bitcore)/`, protocol `170009` Sapling.
- **`bitcore`** — Node v8.17.0 running `bitcore-node`, serving the explorer on
  `:3001`. In `connect` mode it attaches to a running `zerod` and does not own
  zerod's lifecycle.
- **nginx 1.14.0** — TLS terminator and reverse proxy to `127.0.0.1:3001`. UI at
  `/insight`, API at `/insight-api-zero/...`.

The stack runs on Node v8.17.0 — the last 8.x, EOL 2019-12-31 — against a
dependency tree frozen circa 2021. A Node bump would force revalidating that whole
tree, with native rebuilds for zeromq, leveldown, and secp256k1. The posture is
therefore *harden in place*.

### 1.1 Ports

Every port is the conventional default for its role — nothing is renumbered.
Live-verified with `ss -tlnp`.

| Purpose | Process | Default | Value | Bind | Set where |
|---|---|---|---|---|---|
| P2P | zerod | 23801 | 23801 | `0.0.0.0`+`[::]` | `port=` zero.conf |
| RPC | zerod | 23811 | 23811 | `*`, loopback-confined | `rpcport=` zero.conf |
| ZMQ rawtx | zerod | off | 28332 | `127.0.0.1` | `zmqpubrawtx=` zero.conf |
| ZMQ hashblock | zerod | off | 28332 | `127.0.0.1` | `zmqpubhashblock=` zero.conf |
| Insight HTTP | bitcore | 3001 | 3001 | `*` | `port:` bitcore-node.json |
| HTTP / HTTPS | nginx | 80 / 443 | 80 / 443 | `0.0.0.0`+`[::]` | nginx vhost |

The Zero daemon uses its own family ports (23801/23811), distinct from Bitcoin
(8333/8332) and Zcash (8233/8232), so it never collides with a co-resident
`bitcoind`/`zcashd`. RPC binds `*` but is confined to loopback by
`rpcallowip=127.0.0.1` — Zero RPC has no per-interface bind, so the IP allow-list
is the control. nginx is the only externally reachable surface.

Both ZMQ publishers point at one port (28332) on purpose: zerod opens a single PUB
socket and multiplexes topics over it. The mechanism is in Appendix A.

`rpcworkqueue=1024` — well above the daemon default of 16 — because the API bursts
concurrent RPC and a low queue yields "work queue depth exceeded" 500s.
`getzmqnotifications` is absent in this build, so verify ZMQ with `ss`/`lsof`, not
RPC.

The API mounts at `/insight-api-zero`. The route-naming detail is in Appendix B.

```sh
curl http://127.0.0.1:3001/insight-api-zero/sync          # {status, syncPercentage, height}
curl http://127.0.0.1:3001/insight-api-zero/status?q=getInfo
```

---

## 2. Filesystem layout

Ubuntu 18.04 placement. Where every moving part lives and who owns it.

### 2.1 Binaries

`/home/ubuntu/zero/BIN/`:

| Binary | Role |
|---|---|
| `zerod` | the full node |
| `zero-cli` | RPC client and node control — `stop`, `getblockcount`, `getpeerinfo`, `setban` |
| `zero-tx` | tx utility, rarely used operationally |

These are hand-placed, not packaged, so no apt upgrade touches them. The Node
runtime is not here — it is the nvm install at
`/home/ubuntu/.nvm/versions/node/v8.17.0/bin/node`. System `/usr/bin/node`
(v8.10.0) is unused and must never be resolved by `env node` — the unit pins the
absolute path to avoid exactly that, §4.2.

### 2.2 zerod datadir

`/home/ubuntu/.zero/` — the node's entire state. This is zerod's default for user
`ubuntu`, so `zero.conf` carries no `datadir=` line; the unit pins `-datadir`
anyway for explicitness.

| Item | Path | Notes |
|---|---|---|
| daemon config | `~/.zero/zero.conf` | holds RPC creds; mode 600. Verbatim in [`config/zero.conf`](config/zero.conf) |
| pidfile | `~/.zero/zerod.pid` | written by zerod `-pid`, matched by unit `PIDFile=`. Not a lock |
| env lock | `~/.zero/.lock` | 0-byte advisory fd-lock |
| UTXO set | `~/.zero/chainstate/` | leveldb; `chainstate/LOCK` is fd-locked |
| block files + index | `~/.zero/blocks/`, `~/.zero/blocks/index/` | leveldb; `index/LOCK` fd-locked |
| debug log | `~/.zero/debug.log` | zerod's own log |

zerod creates the datadir tree mode `700` and its config mode `600`; the
credentials in `zero.conf` must not be group- or world-readable.

The Insight-required `zero.conf` directives — full file in [`config/`](config/) —
are `txindex=1`, `insightexplorer=1`, and `experimentalfeatures=1`: the
address/spent indexes and explorer RPCs gate behind them, and `insightexplorer`
itself requires `experimentalfeatures`. `server=1` enables RPC;
`rpcallowip=127.0.0.1` confines it to loopback.

### 2.3 bitcore install

`/home/ubuntu/zero/mynode/`:

| Item | Path | Notes |
|---|---|---|
| node_modules | `~/zero/mynode/node_modules/` | the four explorer packages plus deps. Deployed originals untouched |
| active config | `~/zero/mynode/bitcore-node.json` | connect mode, live. Sample in [`config/bitcore-node.json`](config/bitcore-node.json) |
| rollback config | `~/zero/mynode/bitcore-node.json.spawn.bak` | spawn-mode anchor |
| hand-launch script | `~/zero/mynode/bitcore_start.sh` | one line; manual/legacy path. Sample in [`config/bitcore_start.sh`](config/bitcore_start.sh) |
| legacy stdout log | `~/zero/mynode/start.out` | flat log for the hand-launch path only; the journal is the live sink |

The name `mynode` is the literal example directory from the upstream
`bitcore-node-zero` install instructions — `bitcore-node create mynode && cd
mynode`, verbatim in the package READMEs. Whoever stood the node up followed the
README and kept the placeholder; it carries no meaning beyond "the bitcore-node
app directory." Renaming is safe but pointless, touching `bitcore_start.sh`, both
unit paths, and the `.spawn.bak` for no benefit.

### 2.4 Ownership

The two daemons run as the unprivileged user `ubuntu`, even though systemd
launches them — the unit files set `User=ubuntu`. App and data are owned by
`ubuntu`; the control plane under `/etc` is owned by `root` because that is where
systemd and nginx require it.

| Path | Owner | Mode |
|---|---|---|
| `~/.zero/` datadir | `ubuntu:ubuntu` | dirs 700, `zero.conf` 600 |
| `~/zero/BIN/*`, `~/zero/mynode/**` | `ubuntu:ubuntu` | 755 / 644 |
| `/etc/systemd/system/{zerod,bitcore}.service` | `root:root` | 644 |
| `/etc/nginx/**`, `/etc/systemd/journald.conf` | `root:root` | 644 |
| `/etc/letsencrypt/live/**` TLS keys | `root:root` | key 600 |

Keep this split. The daemons must not run as `root`, and the datadir must not sit
under a root-owned tree — either would force `sudo` for routine work and widen the
blast radius of an explorer compromise, since the explorer parses untrusted P2P/tx
data. Editing a unit needs `sudo` and `daemon-reload`; operating the
services needs `sudo` because they are *system* units.

### 2.5 System config

Root-owned, edited with `sudo`:

| Item | Path | After editing |
|---|---|---|
| zerod unit | `/etc/systemd/system/zerod.service` | `daemon-reload` |
| bitcore unit | `/etc/systemd/system/bitcore.service` | `daemon-reload` |
| boot symlinks | `…/multi-user.target.wants/{zerod,bitcore}.service` | via `systemctl enable/disable` |
| nginx vhost | `/etc/nginx/sites-enabled/default` → `sites-available/default` | `nginx -t && systemctl reload nginx` |
| journald | `/etc/systemd/journald.conf` | `systemctl restart systemd-journald` |

Placement rules that bite on 18.04 / systemd 237:

- **Admin tree.** Units go in `/etc/systemd/system/`, the admin override tree, which
  takes precedence over the distro's `/lib/systemd/system/`.
- **System units, not user units.** These run from boot independent of any login.
  *User* units under `~/.config/systemd/user/` only run while that user has an
  active login session and die at logout unless lingering is enabled — wrong for a
  boot-persistent server daemon.
- **The enable symlink.** `systemctl enable zerod` creates the symlink
  `…/multi-user.target.wants/zerod.service → /etc/systemd/system/zerod.service`.
  That symlink is the only thing that starts the unit at boot; `systemctl start`
  affects only the running session and does not survive reboot. So "enabled" means
  symlinked into the boot target and "active" means running now — independent
  states, and a unit must be enabled to come up after a reboot.
- **daemon-reload.** After any unit edit you must `sudo systemctl daemon-reload`;
  237 caches parsed units and will not see the change otherwise.

The files in [`config/`](config/) are reference copies, not a deployment
mechanism. They are read, diffed, and copied by hand to their real `/etc/...` and
`~/...` locations; nothing in the running system points at the directory. Treat it
as documentation of the desired on-disk state.

---

## 3. Operating modes — connect vs spawn

bitcore's `bitcoind` service can obtain its node two ways. The live mode is
`connect`.

### 3.1 connect — live

systemd runs `zerod` as an independent service; bitcore only opens an RPC client
and ZMQ subscriber against the already-running daemon. `bitcoind.js.start()` skips
`_spawnChildProcess` entirely — no child, no respawn loop, no spawn-time fd-leak
path. A bitcore restart re-attaches to the still-running zerod instead of launching
a rival. This is the correct coupling: zerod authoritative and independent, bitcore
the follower.

The live config, verbatim [`config/bitcore-node.json`](config/bitcore-node.json):

```json
"bitcoind": {
  "connect": [{
    "rpchost": "127.0.0.1", "rpcport": 23811,
    "rpcuser": "...", "rpcpassword": "...",
    "zmqpubrawtx": "tcp://127.0.0.1:28332",
    "zmqpubhashblock": "tcp://127.0.0.1:28332"
  }]
}
```

RPC and ZMQ values must match `zero.conf`. Do not keep a `spawn` block alongside
`connect` — both enabled pushes two entries into the node pool and re-introduces
the spawn path.

A service's string appears twice and must match exactly: each entry in the
top-level `services` array is also the key bitcore-node looks up in `servicesConfig`
(it is the service name, the module `require()` target, and the config key, all the
same string). Renaming a service in one place but not the other silently drops that
service's config.

### 3.2 spawn — rollback anchor

In spawn mode bitcore launches and owns zerod as a double-forked child. This is the
legacy mode and the documented fallback;
[`config/bitcore-node.json.spawn.bak`](config/bitcore-node.json.spawn.bak) is the
revert anchor, carrying `startRetryCount: 60`. Spawn mode is hazardous and is not
the live mode: a bitcore crash orphans its zerod, any bitcore restart then tries to
launch a second zerod against `~/.zero`, collides on the datadir lock, and spirals
into EMFILE. Keep it only as the labelled rollback path, §5.4.

### 3.3 zerod still syncing when bitcore connects

`Requires=`/`After=zerod.service` only guarantee zerod's unit has started, not that
its data RPCs are answering. On a cold or initial load, chainstate verification can
take a long time — an initial blockchain download and verify can run 7–8 hours.

zerod's RPC server binds and accepts connections very early and does not wait for
sync to finish. But until warmup completes, every data call — `getbestblockhash`,
`getblock`, `getblockcount` — returns JSON-RPC error code `-28` with a message such
as `Loading block index…` / `Verifying blocks…` / `Rewinding blocks…`. "RPC up" and
"node ready" are different states: the socket answers throughout sync, but the
answers are `-28` rejections until it is done. `getblockchaininfo` and `getinfo` do
respond during warmup and show `verificationprogress` climbing toward 1.0 — that is
the readiness signal to poll.

Two layers cover the gap:

1. **bitcore retries through warmup.** `_loadTipFromNode` (`error/bitcoind.js:852`)
   calls `getBestBlockHash`, recognizes `err.code === -28`, logs the warmup message
   at warn, and returns the error so `async.retry` tries again
   (`error/bitcoind.js:855-857`). The budget is `startRetryCount × interval` —
   stock 60 × 5 s = 5 min. The staged hardening replaces the flat loop
   with capped exponential backoff and a single give-up `log.error`
   (`error/bitcoind.js:762-784`). Repeated warn lines carrying zerod's
   `-28` message in the journal during initial sync are the expected signature, not
   a fault.
2. **systemd retries the unit.** When the in-process budget is exhausted, bitcore
   exits non-zero and `Restart=on-failure` (`RestartSec=10`) relaunches it, which
   retries the connect. During a long initial sync bitcore bounces in a slow loop
   until zerod answers, then connects and stays up.

A 7–8 hour sync exceeds both the in-process budget and the `StartLimitBurst=5 /
StartLimitIntervalSec=300` flap cap — bitcore would land in `failed` long before
zerod is past warmup. For an initial-sync scenario, decouple: keep bitcore stopped,
watch zerod's `verificationprogress` reach ~1.0, then start bitcore once data RPCs
answer. Steady-state restarts on an already-synced zerod never hit this — chainstate
reload there is seconds to minutes, well inside the budget.

```sh
sudo systemctl stop bitcore
# poll progress — getblockchaininfo answers during warmup:
watch -n30 'zero-cli -datadir=/home/ubuntu/.zero getblockchaininfo | grep -E "blocks|verificationprogress"'
# gate on a data call succeeding — getbestblockhash returns -28 until ready:
until zero-cli -datadir=/home/ubuntu/.zero getbestblockhash >/dev/null 2>&1; do sleep 30; done
sudo systemctl start bitcore
```

### 3.4 zerod exits while bitcore expects it running

This is the case the unit coupling exists for.

- **systemd restarts zerod.** `zerod.service` has `Restart=on-failure`,
  `RestartSec=15`. The dead process's fd-locks were auto-released by the kernel on
  reap, §5.2, so the new instance re-acquires the datadir cleanly.
- **bitcore does not self-heal on its own.** Two facts compound. First, `Requires=`
  propagates stop/start but a unit's own auto-`Restart` is not a stop that cascades
  to dependents, so a plain `Requires` would leave bitcore running across a zerod
  restart. Second, bitcore's RPC client does not re-establish on a mid-run
  connection drop — the retry logic only runs at initial connect. After zerod dies,
  bitcore's `_tryAllClients` fail against the dead socket and ZMQ stops delivering;
  bitcore would sit there broken.
- **`PartOf=zerod.service` is the fix**, present on `bitcore.service`. It makes a
  restart of zerod cascade a restart to bitcore, so when zerod bounces bitcore is
  restarted right behind it and cleanly re-connects. `After=zerod.service`
  preserves ordering during the cascade. `PartOf` is one-directional — a bitcore
  crash leaves zerod untouched.

zerod is master: independent lifecycle, owns the datadir, restarts itself. bitcore
is follower: `Requires` + `After` + `PartOf` zerod, restarting when it fails or
when zerod restarts and re-connecting each time.

---

## 4. Operations

### 4.0 Installing from scratch

The order below stands up the whole stack on a clean Ubuntu 18.04 host. zerod's own
install and general configuration follow Zero's upstream documentation; only the
Insight-specific pieces are spelled out here.

1. **Node runtime.** Install nvm and `nvm install 8.17.0`. Everything below assumes
   that interpreter at `/home/ubuntu/.nvm/versions/node/v8.17.0/bin/node`; the
   system `/usr/bin/node` is never used (§2.1).

2. **zerod.** Build/place `zerod`, `zero-cli`, `zero-tx` in `~/zero/BIN` per Zero's
   own docs, then write `~/.zero/zero.conf`. Use Zero's documentation for the general
   directives; the **Insight-required** ones are not optional and are the reason this
   config differs from a plain node — full file in
   [`config/zero.conf`](config/zero.conf):

   ```ini
   txindex=1                 # full tx index — Insight needs arbitrary tx lookup
   insightexplorer=1         # address/spent indexes + explorer RPCs
   experimentalfeatures=1    # required by insightexplorer
   server=1                  # enable RPC
   rpcallowip=127.0.0.1      # confine RPC to loopback (no per-iface bind on Zero)
   rpcport=23811
   port=23801
   rpcworkqueue=1024         # API bursts concurrent RPC; default 16 yields 500s
   zmqpubrawtx=tcp://127.0.0.1:28332
   zmqpubhashblock=tcp://127.0.0.1:28332
   uacomment=bitcore
   rpcuser=<REDACTED>        # must match bitcore-node.json (§3.1)
   rpcpassword=<REDACTED>
   ```

   Set `zero.conf` mode 600. Start zerod and let it complete its initial block
   download and verify before bringing bitcore up — that first sync runs 7–8 hours
   (§3.3). `txindex=1`/`insightexplorer=1` on a pre-existing datadir force a one-time
   reindex, so enable them before first sync if possible.

3. **bitcore app.** Create the app dir the upstream way —
   `bitcore-node create mynode` — which is where the literal name `mynode` comes from
   (§2.3), then install the four explorer packages into
   `~/zero/mynode/node_modules/` (`bitcore-lib-zero`, `bitcore-node-zero`,
   `insight-api-zero`, `insight-ui-zero`). The package set and pinned versions are in
   InsightPort.md.

4. **UI build.** `insight-ui-zero` ships as source, not a built bundle: its client
   assets are compiled by **bower 1.2.8** (fetches the AngularJS ~1.5.8 / Bootstrap
   ~3.1.1 front-end deps into `public/lib`) and **grunt 0.4.2** (concat/minify into
   the served bundle). The UI does not render until this build has run inside
   `node_modules/insight-ui-zero/`. These tool versions are as old as the rest of the
   tree and must be matched on the Node 8 runtime — see InsightPort.md for the build
   chain detail.

5. **bitcore-node.json.** Copy [`config/bitcore-node.json`](config/bitcore-node.json)
   to `~/zero/mynode/bitcore-node.json` and fill in real `rpcuser`/`rpcpassword`
   matching `zero.conf` step 2 (the reference copy ships redacted; delete its
   `_comment` line). This is connect mode. Keep the spawn variant as
   `bitcore-node.json.spawn.bak` for rollback (§3.2). The service-string matching rule
   in §3.1 applies to any edit here.

6. **systemd units.** Copy both units into the admin tree, reload, enable, start:

   ```sh
   sudo cp config/zerod.service config/bitcore.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now zerod.service        # zerod first; let RPC come ready (§3.3)
   sudo systemctl enable --now bitcore.service       # then bitcore
   ```

   `enable --now` both enables the boot symlink and starts now (§2.5); this is the
   exact inverse of the rollback `disable --now` in §5.4. Then apply the supporting
   root-owned config — `journald.conf`, the nginx vhost, `logrotate-bitcore` — each
   per its row in §2.5.

7. **Verify.** Run the §4.6 reboot checklist: exactly one zerod parented to systemd,
   connect mode, API serving the live tip.

The hand-launch path (§4.1) is a fallback for diagnostics and the spawn rollback; a
fresh install goes straight to the systemd units in step 6.

### 4.1 Launch

The supported runtime is systemd, §4.2. The hand-started path below is the
test/diagnostic fallback; order matters.

```sh
# zerod by hand:
/home/ubuntu/zero/BIN/zerod -daemon -conf=/home/ubuntu/.zero/zero.conf \
    -datadir=/home/ubuntu/.zero -pid=/home/ubuntu/.zero/zerod.pid
# wait for RPC to answer (returns -28 until warmup ends, §3.3):
until /home/ubuntu/zero/BIN/zero-cli -datadir=/home/ubuntu/.zero getbestblockhash >/dev/null 2>&1; do sleep 5; done

# bitcore by hand, spawn mode:
cd /home/ubuntu/zero/mynode
[ -s start.out ] && mv start.out "start_$(date +%Y%m%d-%H%M%S).out"   # move aside, don't clobber
./bitcore_start.sh > start.out 2>&1 &
```

`bitcore_start.sh` is the one-line manual launcher — sample in
[`config/bitcore_start.sh`](config/bitcore_start.sh) — running
`./node_modules/bitcore-node-zero/bin/bitcore-node start`. Move the prior `start.out`
aside before relaunching rather than truncating it; the redirect would otherwise
overwrite the only record of the last hand-launch run. This flat log is the
hand-launch path only — under systemd everything goes to the journal (§6).

Identifying the running bitcore: it rewrites its argv at startup to the literal
string `bitcore`, which is also why the unit and `uacomment` carry that name. So
`pgrep -f bitcore-node` finds nothing, and `pgrep -f bitcore` also catches your own
shell on the word. Identify it deterministically:
`systemctl show -p MainPID --value bitcore.service`, or in spawn mode as the parent
of the spawned zerod, `ps -o ppid= -C zerod`.

### 4.2 systemd model

Both units are deployed, enabled, and boot-persistent. Full text in
[`config/zerod.service`](config/zerod.service) and
[`config/bitcore.service`](config/bitcore.service); the load-bearing directives:

**`zerod.service`** — `Type=forking` with `PIDFile=`; zerod `-daemon` double-forks
and writes the pidfile, so `-pid`/`-datadir`/`PIDFile=` must all agree.
`ExecStop=zero-cli -conf=… -datadir=… stop` — this is what makes a `systemctl stop`
graceful: systemd runs the RPC `stop` rather than signalling the process, so zerod
flushes chainstate and releases locks. `After=`+`Wants=network-online.target`.
`TimeoutStartSec/StopSec=300` for cold verify and clean flush. `LimitNOFILE=65536`.
`Restart=on-failure`, `RestartSec=15`. It sets no `Standard*` directives, so it
inherits the systemd default `StandardOutput=journal` — but `-daemon` double-forks
and detaches before writing anything substantial, so that inherited stream stays
nearly empty; zerod's real log is `~/.zero/debug.log` (§2.2), not the journal. Only
the `Type=forking` launch/exit lines land under `journalctl -u zerod`.

**`bitcore.service`** — `Type=simple`. `After=zerod.service network-online.target`,
`Requires=zerod.service`, `PartOf=zerod.service`. `Restart=on-failure`,
`RestartSec=10`. Three 18.04 / 237 traps, each load-bearing:

- `StartLimitIntervalSec`/`StartLimitBurst` go in `[Unit]`, not `[Service]`. Moved
  to `[Unit]` in systemd v230; on 237 the `[Service]` form is silently ignored,
  disabling the flap cap of 5 starts / 300 s.
- `StandardOutput=journal` **and** `StandardError=journal`, not `append:`.
  `append:/path` needs systemd ≥ 240; on 237 it is a parse error. Both of bitcore's
  streams go to the journal, tagged `SyslogIdentifier=bitcore` — unlike zerod,
  bitcore runs in the foreground (`Type=simple`) so its full stdout/stderr is
  captured. This is the live sink that replaces the hand-launch `start.out`.
- Absolute nvm node plus `Environment=PATH=…/v8.17.0/bin:…`. systemd's minimal PATH
  excludes nvm, so `env node` would fail or pick system `/usr/bin/node` v8.10.0. Pin
  both the PATH and the absolute node path.

### 4.3 Routine control

`systemctl` is the tool for routine administration — start, stop, restart, and the
upgrade workflows. A `systemctl stop zerod` is graceful via the unit's `ExecStop`
(§4.2).

```sh
# restart only bitcore — reconnects to the running zerod, chain stays up:
sudo systemctl restart bitcore.service
# restart the whole stack — PartOf= pulls bitcore with zerod:
sudo systemctl restart zerod.service
# graceful full stop / start:
sudo systemctl stop bitcore.service && sudo systemctl stop zerod.service
sudo systemctl start zerod.service && sudo systemctl start bitcore.service
# logs and health:
journalctl -u zerod -f ;  journalctl -u bitcore -f
systemctl is-active zerod bitcore
curl -s http://127.0.0.1:3001/insight-api-zero/sync; echo
```

### 4.4 Node control with zero-cli

`zero-cli` is for hands-on work with the node itself — direct RPC queries, and a
manual graceful stop when running off systemd:

```sh
zero-cli -datadir=/home/ubuntu/.zero getblockchaininfo     # height, verificationprogress
zero-cli -datadir=/home/ubuntu/.zero getpeerinfo
zero-cli -datadir=/home/ubuntu/.zero stop                  # graceful stop, off-systemd
```

Under systemd, prefer `systemctl stop` so systemd's own state stays consistent;
reach for `zero-cli stop` directly only when systemd is not managing the process.

### 4.5 Shutdown reference

There is one graceful path and a small set of escalations. A graceful stop lets
zerod flush its in-memory chainstate and release locks cleanly. A `kill -9`
(SIGKILL) cannot be trapped, so zerod skips the flush and the next start does a
multi-hour dirty-shutdown reindex — that single fact is the reason graceful is
preferred everywhere below, and it is not repeated again.

| Context | Stop with |
|---|---|
| Routine, under systemd | `sudo systemctl stop zerod` — graceful via `ExecStop` |
| Hands-on / off systemd | `zero-cli ... stop` — graceful |
| Process won't respond to a graceful stop | `kill` (SIGTERM); SIGKILL only if SIGTERM is ignored, accepting the reindex |
| Deliberately simulating a crash in testing | `kill` — systemd's `Restart=on-failure` should react |

`systemctl stop` and `kill` test different things: `systemctl stop` exercises the
clean-shutdown path (systemd should not restart), `kill` exercises the crash path
(systemd should restart). Use the one that matches the behavior you are verifying.

### 4.6 Reboot

Both units are enabled, so a reboot needs no manual action: systemd brings zerod up
first (`After=network-online.target`), then bitcore (gated by `After`+`Requires`).
A transient bitcore restart in the first minute — losing the RPC-ready race, §3.3 —
is normal and self-heals within the StartLimit. Verify after:

```sh
systemctl is-active zerod.service bitcore.service     # active / active
pgrep -x zerod | wc -l                                # exactly 1 — no duplicate
ps -o pid,ppid,cmd -C zerod                           # PPID must be 1, systemd
grep -E 'spawn|connect' ~/zero/mynode/bitcore-node.json   # connect
curl -s http://127.0.0.1:3001/insight-api-zero/sync; echo
```

The decisive check is exactly one zerod, parented to systemd, in connect mode, with
the API serving the live tip.

---

## 5. Recovery

### 5.1 Reviewing a crash

```sh
journalctl -u bitcore -b --no-pager | tail -n 80
journalctl -u zerod   -b --no-pager | tail -n 80
journalctl -u bitcore --since "1 hour ago" --no-pager
```

Match the signature against the catalogued crashes in InsightFix.md.

### 5.2 Lock files

The datadir locks are advisory fd-locks, kernel-owned and keyed to the process —
not state written into the file. `.lock`, `chainstate/LOCK`, and `blocks/index/LOCK`
are 0-byte targets; `zerod.pid` is not a lock, just PID text.

| Situation | Action |
|---|---|
| Crash, process died | Kernel auto-released every fd-lock on reap. Nothing to clear — restart works |
| Hang, process alive but wedged | Locks are held correctly, no corruption. Kill the holder gracefully, §5.3 |
| "Cannot obtain a lock" | Another zerod is alive, not a stale file. `sudo lsof ~/.zero/.lock` to find the holder, stop it gracefully, confirm gone, start |
| Removing a `LOCK`/`.lock` | Only when `lsof` shows no holder and the datadir still refuses to open — and that state means a dirty shutdown, so start with `zerod -reindex`, do not just delete |

Do not `rm` a lock to free it. `rm` removes the directory entry, but the kernel
fd-lock lives on the open file description, not the name, so deleting it does not
release the lock while a holder is alive — and it removes the guard against a second
writer corrupting the datadir. Identify the holder with `lsof`, stop it gracefully,
confirm it is gone, then start.

### 5.3 Hang detection

A hung process has not exited, so `Restart=on-failure` never fires — systemd sees it
as running and leaves it wedged. `TimeoutStartSec/StopSec=300` only bound the
transition phases; a hang during start or stop is SIGKILLed after 300 s, but a
steady-state hang after a clean start is invisible to systemd.

There is no liveness watchdog deployed today. To recover a hang now: confirm the
stall (the API stops answering and `getblockcount` stops advancing while peers are
present), then `sudo systemctl kill zerod` to convert the hang into a crash — the
fd-locks auto-release on reap, `PartOf` pulls bitcore down, and both come back via
their own `Restart=`. A proposed automatic watchdog is in Appendix C, clearly marked
as unimplemented.

### 5.4 Rolling back to spawn mode

```sh
sudo systemctl disable --now bitcore zerod
/home/ubuntu/zero/BIN/zero-cli -datadir=/home/ubuntu/.zero stop 2>/dev/null; sleep 5
cd /home/ubuntu/zero/mynode && cp bitcore-node.json.spawn.bak bitcore-node.json
./bitcore_start.sh > start.out 2>&1 &
```

The units are additive and the datadir is never modified, so rollback returns the
exact prior state.

### 5.5 Disk full

The journal is capped (§6) so it cannot fill the disk; the legacy flat `start.out`
is the one log that can grow unbounded if the node is still writing to it.

```sh
df -h /
du -xh /home/ubuntu /var/log 2>/dev/null | sort -rh | head -20
journalctl --disk-usage
sudo journalctl --vacuum-size=1G
: > /home/ubuntu/zero/mynode/start.out     # truncate legacy flat log if present, while stopped
```

A full disk can wedge zerod mid-write into a dirty shutdown. After clearing space,
if zerod will not start clean, `zerod -reindex` repairs the leveldb. Stop it
gracefully (§4.5) before reindexing.

### 5.6 Breaking upgrades

`systemctl` drives all of these. Both flavors are gated on revalidation; the full
version matrix and walls are in InsightPort.md.

- **OS / nginx / systemd, via apt.** The binaries in `~/zero/BIN` and the nvm Node
  are hand-placed and unaffected by apt, but a systemd major bump can change
  directive semantics — the `StartLimit*` move, `append:` availability. Re-check the
  units with `systemd-analyze verify` after any systemd upgrade.
- **Node / npm dependency tree.** Frozen circa 2021 on Node 8; 8→10 is the wall,
  forcing native rebuilds of zeromq, leveldown, and secp256k1. Do not swap
  dependency versions in place the way the staged `error/*.js` source files are
  swapped — a version bump such as bn.js 2.x→5.x needs `npm install` plus the lib
  test suite plus smoke tests; track each as its own test-gated change. The crash
  fixes in `error/` are deliberately decoupled from any dependency upgrade so they
  ship independently.

Upgrade discipline: snapshot `bitcore-node.json` and the units, note the height
(`zero-cli getblockcount`), `sudo systemctl stop bitcore` then `zerod`, upgrade,
`systemd-analyze verify` the units, start zerod and wait for RPC, start bitcore,
then run the §4.6 verification. Roll back via §5.4 if any check fails.

---

## 6. Logging

The single sink is the journal — both units log `StandardOutput=journal` and
`StandardError=journal`, giving per-boot separation and rotation with no flat-file to
grow unbounded. Storage is persistent (`/var/log/journal/` exists, so the journal
survives reboots), but the size/retention caps must be applied deliberately — the
journald default cap is 10% of the filesystem, large enough to let the journal grow
to multiple GB. The intended caps live in
[`config/journald.conf`](config/journald.conf):

```ini
[Journal]
SystemMaxUse=1G
SystemMaxFileSize=100M
MaxRetentionSec=1month
```

These are install-time config (§4.0 step 6), not a built-in default; copy the file
into place and `systemctl restart systemd-journald` to enforce them. Read per-run with
`journalctl -u bitcore -b`. logrotate is only needed if a downstream tool must parse
a flat `start.out`; the rule in [`config/logrotate-bitcore`](config/logrotate-bitcore)
uses `copytruncate` because bitcore holds the fd open and will not reopen on a
signal, so logrotate must copy then truncate in place rather than rename. nginx
access/error logs under `/var/log/nginx/` rotate via the distro's
`/etc/logrotate.d/nginx`. zerod's own `~/.zero/debug.log` is separate; consult it
for peer `Misbehaving` lines.

---

## 7. nginx

TLS terminates at nginx — Certbot certs under `/etc/letsencrypt/live/` — and it
reverse-proxies cleartext to bitcore on `:3001`. Single site file,
[`config/nginx-default`](config/nginx-default), a symlink target in
`sites-available/`; `conf.d/` is empty and `nginx -t` passes. The explorer vhosts
301 `/` to `/insight` and `proxy_pass` everything else to `127.0.0.1:3001/`. The API
is reachable through the same proxy at `/insight-api-zero/...`.

There are no `proxy_read_timeout`, `proxy_buffering`, or `client_max_body_size`
overrides, so defaults apply. The default `proxy_read_timeout 60s` is fine for short
JSON; raise it only if a long address-history call hits the ceiling. After editing,
`sudo nginx -t && sudo systemctl reload nginx`.

---

## Appendix A — Developer internals

For someone working on the explorer code, not operating the server.

### A.1 ZMQ topic multiplexing on one port

ZMQ here is publish/subscribe push, not request/response RPC. zerod opens a single
ZMQ PUB socket on `tcp://127.0.0.1:28332` and multiplexes topics over it: each
message carries a topic frame — `rawtx`, `hashblock` — as its first part, then the
payload. A subscriber filters by topic frame, so one socket carries many topics.
Pointing both `zmqpubrawtx` and `zmqpubhashblock` at the same address is therefore
the normal configuration: zerod binds the address once and publishes both topics on
it, and bitcore's `bitcoind` service opens one SUB socket and subscribes to both
frames.

The upstream `bitcore-node` docs split topics across ports — 30611/30622/30633 —
only when running multiple independent daemons, so each needs its own non-colliding
socket. With one daemon, one port is correct.

zerod exposes only these two topics; there is no `zmqpubrawblock`/`zmqpubhashtx`
here, and there is no ZMQ heartbeat — a silent socket means "no new tx or blocks,"
not "dead," so liveness must be checked another way (§5.3).

### A.2 connect vs spawn in code

`bitcoind.js.start()` branches on the config: `connect` opens an RPC client and ZMQ
subscriber against a running daemon, while `spawn` calls `_spawnChildProcess` to
launch and own zerod. Both code paths exist in the stock package; the connect-mode
switch is pure configuration in `bitcore-node.json`. The RPC client's retry logic
runs only at initial connect — it does not re-establish on a mid-run drop, which is
why §3.4 relies on `PartOf=` to restart bitcore behind a zerod bounce rather than on
in-process reconnection.

### A.3 RPC warmup and the tip loader

`_loadTipFromNode` (`error/bitcoind.js:852`) calls `getBestBlockHash`, special-cases
`err.code === -28` (the warmup rejection), logs at warn, and returns the error so
`async.retry` retries. The staged hardening (`error/bitcoind.js:762-784`; crash #1)
replaces the flat retry loop with capped exponential backoff and a single give-up
`log.error`.

### A.4 Crash catalog

The crashes referenced by number in the code notes. Full signatures, `.tail`
captures, and staged `error/*.js` fixes are in InsightFix.md.

| # | Signature | Notes |
|---|---|---|
| 1 | `RangeError` in the tx parser | parsing untrusted P2P/tx data; staged backoff at `error/bitcoind.js:762-784` |
| 2 | `EMFILE` | spawn-mode fd exhaustion from an orphaned-then-relaunched zerod |
| 3 | `JS heap out of memory` | Node v8 heap limit |
| 4 | `certificate has expired` | non-fatal |

---

## Appendix B — Integrator API

For a third-party app or wallet integrating against the explorer, not the server
admin.

### B.1 Route prefix

`bitcore-node.json` sets no `routePrefix`, so each service's prefix defaults to its
service name: `insight-api-zero/lib/index.js:58-61` sets `routePrefix = this.name`
when undefined, and `bitcore-node-zero/lib/service.js:85-86` returns `this.name`. The
API is therefore mounted at `/insight-api-zero`. This is the intended path for this
fork — the upstream `insight-ui-zero` README documents exactly
`http://localhost:3001/insight-api-zero/`, and the UI's compiled config calls that
same prefix. The conventional `/insight-api` used by the original BitPay Insight
returns 404 here.

The prefix is fork-name-derived, so it drifts per project:

| Stack | API prefix |
|---|---|
| BitPay Insight (Bitcoin) | `/insight-api` |
| Zcash (str4d `insight-api-zcash`) | `/insight-api-zcash` |
| Zero (this) | `/insight-api-zero` |

The Zero packages are a direct rename-fork of str4d's Zcash Insight, so the only
route difference from Zcash is the `-zero` suffix.

To rename ours, add `"routePrefix": "insight-api"` under
`servicesConfig."insight-api-zero"` and update the UI's expected prefix to match —
changing one side alone breaks the UI. That is a deliberate change, not a fix.

### B.2 Endpoints

```sh
curl http://127.0.0.1:3001/insight-api-zero/sync            # {status, syncPercentage, height}
curl http://127.0.0.1:3001/insight-api-zero/status?q=getInfo
```

Externally these are reached through nginx at `/insight-api-zero/...` on the
explorer host.

---

## Appendix C — Suggestions (unimplemented)

Not tested, not supported, not deployed. Recorded for future work.

### C.1 Automatic liveness watchdog

§5.3 covers manual hang recovery. An automatic version would be a systemd timer and
oneshot pair that probes real work and, on stall, converts the hang into a crash so
the existing `Restart=on-failure` recovers. systemd's native `WatchdogSec` is not
usable here — it requires the process to call `sd_notify(WATCHDOG=1)`, which
bitcore/zerod do not — so an external prober is the only no-code-change option.

```ini
# bitcore-health.service  — Type=oneshot
[Service]
Type=oneshot
ExecStart=/usr/bin/curl -fsS -m 10 http://127.0.0.1:3001/insight-api-zero/sync
ExecStart=/home/ubuntu/zero/BIN/zero-cli -datadir=/home/ubuntu/.zero getblockchaininfo
OnFailure=bitcore-recover.service
```
```ini
# bitcore-health.timer
[Timer]
OnBootSec=10min            # skip the cold-sync window, §3.3
OnUnitActiveSec=2min
[Install]
WantedBy=timers.target
```
```ini
# bitcore-recover.service  — Type=oneshot
[Service]
Type=oneshot
ExecStart=/bin/systemctl kill --signal=SIGTERM zerod.service
```

Design points: the escalation sends SIGTERM, not SIGKILL, so zerod can still flush;
the probe uses `getblockchaininfo`, which answers during warmup, rather than a data
call that returns `-28` during a normal reindex; and the `OnBootSec=10min` delay
keeps it from firing on a still-syncing but healthy node. A richer prober could
compare consecutive `getblockcount` values across two ticks and escalate only if the
height has not moved while peers exist, to avoid killing a merely-idle node.
