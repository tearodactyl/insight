# InsightFix — Crash signatures, mitigations, and staged hardening

Companion to [Insight.md](Insight.md) (overall description, document map, operations)
and [InsightPort.md](InsightPort.md) (lineage, ecosystem, versions, porting).

This document is the tight, operational record of how the Zero Insight explorer
(`bitcore` process, Node v8.17.0, host `toru`) has crashed in production, what the
captured logs show, and the fixes — both the **first batch already staged** and the
**rest still to merge**. Each fix records the *shape* of the change and why, with
short snippets, and points at the staged files in `error/` by line number.

**Source of truth for the crashes:** `/home/ubuntu/zero/NSAVE/errors/` on `toru` —
saved log tails of the `bitcore` process dying. Referenced captures:

| Capture | Date | Crash it documents |
|---|---|---|
| `rangeError.save` | 2022-09 | #1 tx-parser `RangeError` |
| `start2.tail` | 2022-09 | #1 (recurrence) |
| `start4.tail` | 2023-06 | #1 (recurrence) |
| `start5.tail` | 2024-05 | #4 expired-cert price feed |
| `start6.tail` | 2025-06 | #3 JS-heap OOM |
| `start11.tail` | 2026-06-20 | #2 EMFILE fd-leak |

**Staged ≠ deployed.** All fixes live as edited copies under `error/`, each
`node --check`-clean and `diff -u`-verified against the deployed original. The
deployed `node_modules` originals under `insight-api-zero/`, `bitcore-lib-zero/`,
and `bitcore-node-zero/` are **untouched**. Nothing is deployed to toru without an
explicit go-ahead. See [Insight.md](Insight.md) Operations for the deploy/rollback
procedure.

---

## 1. The four production crash signatures (summary)

| # | Signature | First seen | Fatal? | Root cause | Fix status |
|---|---|---|---|---|---|
| 1 | `RangeError: Index out of range` in tx parser | 2022-09 (recurs ×2 2022-09, 2023-06; absent 2024–2026) | Yes — kills process | Malformed/truncated tx buffer off the ZMQ `rawtx` topic makes `Transaction.fromBuffer` read past the end; the throw is uncaught in the event handler. **Two doors** (inv path + rawtx path). | **Staged (batch 1):** `error/index.js`, `error/bitcoind.js`, `error/transaction.js` |
| 2 | `Error: EMFILE: too many open files` | 2026-06-20 | Yes | Stale datadir lock → ~5 s restart loop leaks ZMQ sockets/fds until `ulimit -n`. `startRetryCount: 60` made it worse. | **Resolved two ways:** root cause removed by connect-mode cutover (live); fd-leak + backoff hardened in `error/bitcoind.js` |
| 3 | `FATAL ERROR: ... JS heap out of memory` (abort + core) | 2025-06 | Yes | One Express `response.send()` builds a ~163 MB string (163144806 bytes, `response.js:107`) — oversized unpaginated API response — past the ~1.4 GB Node-8 heap. | **Staged (batch 1):** `error/addresses.js` |
| 4 | `Error: certificate has expired` | 2024-05 (repeats ~10 min) | No — kept serving | Outbound price-feed TLS fails under Node 8.17's stale bundled CA roots. | **Staged (batch 1):** `error/currency.js` |

The Node-8 / OpenSSL-1.0.2 constraint behind #4 (and the upgrade wall) is documented
in [InsightPort.md](InsightPort.md) §2. The lock-file mechanics behind #2 are in
[Insight.md](Insight.md) Operations (crash recovery). Those are not repeated here.

---

## 2. The first batch (staged in `error/`)

Five files, all `node --check`-clean and diffed against the deployed originals.
Three of them (`index.js`, `bitcoind.js`, `transaction.js`) together close crash
#1; `addresses.js` closes #3; `currency.js` closes #4. `bitcoind.js` additionally
carries the #2 fd-leak/backoff work (consolidated in §3 below).

| Staged file | Replaces (deployed) | Closes | Lines |
|---|---|---|---|
| `error/index.js` | `insight-api-zero/lib/index.js` | #1 inv door | 347 |
| `error/bitcoind.js` | `bitcore-node-zero/lib/services/bitcoind.js` | #1 rawtx door, #2 fd-leak/backoff | 2273 |
| `error/transaction.js` | `bitcore-lib-zero/lib/transaction/transaction.js` | #1 diagnostic context | 1415 |
| `error/addresses.js` | `insight-api-zero/lib/addresses.js` | #3 OOM | 285 |
| `error/currency.js` | `insight-api-zero/lib/currency.js` | #4 cert | 116 |

### 2.1 Crash #1 — tx-parser `RangeError` (two doors)

**Symptom.** From `rangeError.save` / `start2.tail` / `start4.tail`:

```
RangeError: Index out of range
  at BufferReader.readUInt32LE (bitcore-lib-zero/lib/encoding/bufferreader.js:81)
  at Transaction.fromBufferReader (bitcore-lib-zero/lib/transaction/transaction.js:366)
  at Transaction.fromBuffer (bitcore-lib-zero/lib/transaction/transaction.js:350)
  at InsightAPI.transactionEventHandler (insight-api-zero/lib/index.js:290)
  at Bitcoin._zmqTransactionHandler (bitcore-node-zero/lib/services/bitcoind.js:647)
```

zerod publishes a raw tx on the ZMQ `rawtx` topic → the handler calls
`new Transaction().fromBuffer(txBuffer)`. For a malformed/truncated frame,
`BufferReader.readUInt32LE` reads past the end and throws `RangeError`. Nothing
catches it → uncaught exception → Node tears the whole process down (logs then
show shutdown + `ECONNREFUSED` on the next request). Trigger is a bad/partial ZMQ
frame or a non-standard tx the parser desyncs on. Present only in 2022–2023 logs,
absent 2024–2026, so rare — but fatal.

**Fix shape — validate the frame, then parse inside try/catch, at *both* parse
sites.** Size-up first so an empty/truncated/absurd frame is rejected cheaply
before the parser touches it; the try/catch is the backstop for frames that pass
the size check but are still malformed (bad varint counts). One bad frame is
logged and dropped instead of killing the process. **Crash #1 has two doors and
both must be shut** — deploying only one leaves the other wide open:

- **Door 1 — inv path** (`insight-api-zero/lib/index.js`). Staged in
  `error/index.js`: constants `InsightAPI.MIN_TX_BYTES = 10` / `MAX_TX_BYTES = 2 MB`
  (`error/index.js:294`), guard + try/catch in `transactionEventHandler`
  (`error/index.js:297-320`). Logger is reached as `this.node.log` (there is no
  top-level `log` in that file; inside the handler `this` is the InsightAPI
  instance):

  ```js
  // error/index.js — transactionEventHandler
  if (!Buffer.isBuffer(txBuffer) ||
      txBuffer.length < InsightAPI.MIN_TX_BYTES ||
      txBuffer.length > InsightAPI.MAX_TX_BYTES) {
    this.node.log.warn('transactionEventHandler: rejecting inv tx frame, bad size: ' + ...);
    return;
  }
  var tx;
  try {
    tx = new Transaction().fromBuffer(txBuffer);
  } catch (err) {
    this.node.log.warn('transactionEventHandler: failed to parse inv tx, skipping: ' + err.message);
    return;
  }
  ```

- **Door 2 — rawtx path** (`bitcore-node-zero/lib/services/bitcoind.js._zmqTransactionHandler`).
  This is the door **nobody had fixed on toru** — it parses every rawtx ZMQ frame
  via `tx.fromString(message)` with no size check and no try/catch, so the same
  `RangeError` kills the process independently of the inv fix. Staged in
  `error/bitcoind.js` (mirrors door 1; full detail in §3). Frame-size guard at
  `error/bitcoind.js:662`, parse try/catch at `error/bitcoind.js:674`.

- **Door 3 — diagnostic context** (`bitcore-lib-zero/lib/transaction/transaction.js`).
  Staged in `error/transaction.js`: re-throws the bare `RangeError` with context
  (buffer length + parsed version) so the cause is identifiable in logs. Not
  required to stop the crash (the two handler try/catches do that), but it makes
  both doors' logs diagnosable.

**Design note — `warn`, not `error`.** A malformed ZMQ frame is *expected*
untrusted input and the process recovers fully by dropping it — that is the
definition of `warn`. `error` is reserved for "the node is broken." This crash
needs **no sibling cherry-pick** — it is local hardening. (Note: this is unrelated
to Pirate's "tx version 5" work, which does not apply to Zero — see
[InsightPort.md](InsightPort.md) §5.)

### 2.2 Crash #3 — JS-heap OOM from an oversized response

**Symptom.** From `start6.tail` (2025-06): `FATAL ERROR: ... JS heap out of memory`,
abort + core dump. One Express `response.send()` built a ~163 MB string
(163144806 bytes, `response.js:107`) on a ~1.4 GB Node-8 heap. Culprit: an
unpaginated API response — most likely `addr/:addr` returning the full `txList`
when `from`/`to` are omitted, or an unbounded `utxo`/`multiutxo` array.

**Fix shape — bound the response before serializing.** Staged in
`error/addresses.js`:

- A `sendChecked(self, res, data)` helper (`error/addresses.js:20`) that
  `JSON.stringify`s the body *inside try/catch* (a serialization throw becomes a
  handled error, not a crash), enforces `MAX_RESPONSE_BYTES = 50 MB`
  (`error/addresses.js:14`) → `413 jsonp` when exceeded (`error/addresses.js:30`),
  then sends. A clean `413` instead of allocating hundreds of MB and aborting.
  Applied to `show`, `utxo`, `multiutxo`, `multitxs`
  (`error/addresses.js:60,183,201,254`).

  ```js
  // error/addresses.js — sendChecked (shape)
  var body;
  try { body = JSON.stringify(data); }
  catch (e) { return res.status(500).jsonp({ error: 'serialization failed' }); }
  if (body.length > MAX_RESPONSE_BYTES) {
    return res.status(413).jsonp({ error: 'Response too large; use pagination (from/to or pageNum).' });
  }
  res.set('Content-Type', 'application/json').send(body);
  ```

- The address summary's txid list is capped at `MAX_TXIDS = 10000`
  (`error/addresses.js:15,103-104`) with `txAppearancesTruncated` /
  `txAppearancesLimit` flags (`error/addresses.js:124`) so callers know to page;
  utxo arrays are rejected past `MAX_UTXOS = 50000`.

**Design note.** Pagination machinery already exists (`transactions.js` paginates
via `pageNum` → `from`/`to`); the fix applies the same discipline to the address
endpoints. `--max-old-space-size=4096` is a *stopgap*, not a fix — it moves the
cliff without removing it; use it alongside, never instead of, the size guard.

### 2.3 Crash #4 — expired-certificate price feed

**Symptom.** From `start5.tail` (2024-05): `Error: certificate has expired`,
repeating ~every 10 min. **Non-fatal** — the explorer keeps serving; only
`currency.js`'s outbound CoinGecko fetch fails. The remote certs are valid; Node
8.17's *bundled* CA roots are too stale to validate them (AddTrust External CA Root
expired 2020-05-30), so TLS is rejected locally.

**Fix shape — trust the OS CA bundle, degrade gracefully.** Staged in
`error/currency.js`:

- **CA trust (the actual handshake fix):** load the OS CA bundle once at module
  load from `CA_CANDIDATES` (`/etc/ssl/certs/ca-certificates.crt`,
  `/etc/pki/tls/certs/ca-bundle.crt`) into `SYSTEM_CA` (`error/currency.js:32`),
  and pass it as `ca` on each request via `requestOpts(url)`
  (`error/currency.js:45-46`). Falls back to Node's default trust if absent.
  `rejectUnauthorized` is **left on** — this fixes verification, it does not
  disable it.

  ```js
  // error/currency.js — module load
  var SYSTEM_CA = (function() {
    for (var i = 0; i < CA_CANDIDATES.length; i++) {
      try { return fs.readFileSync(CA_CANDIDATES[i]); } catch (e) {}
    }
    return null;
  })();
  function requestOpts(url) {
    var opts = { url: url, timeout: 15000 };
    if (SYSTEM_CA) { opts.ca = SYSTEM_CA; }
    return opts;
  }
  ```

- **`error` → `warn`:** a feed failure is expected, recoverable degraded input —
  log `warn` and serve last-known rates, instead of `log.error(err)` every 10 min
  (and the old `console.log(ee)` on parse failure becomes `log.warn`).
- **Guarded `response` deref:** old code read `response.statusCode` even when `err`
  was set (so `response` could be undefined); now `err` returns early and
  `response`/`statusCode === 200` is null-checked; `JSON.parse` is in try/catch.
- **Cold-start bug fixed:** constructor now initializes `this.usd = 0; this.btc = 0;`
  (plus `binanceRate`/`cryptopiaRate`/`timestamp`). Previously neither was set, so
  the first request compared `undefined === 0` (always false) and the freshness
  check never fired on a cold start.
- **Best-effort wrapper:** the whole refresh block is in try/catch so nothing in
  the feed path can throw into the Express handler.

**Design note.** This app-level fix is correct *regardless* of any Node upgrade. A
move to Node 10+ (OpenSSL 1.1.1) would fix the handshake at the runtime layer, but
the two are independent — see [InsightPort.md](InsightPort.md) §2.

---

## 3. `bitcoind.js` hardening — consolidated (the rest, merged into one file)

`error/bitcoind.js` is pulled fresh from the deployed
`bitcore-node-zero/lib/services/bitcoind.js`, `node --check`-clean, with a `diff -u`
showing **exactly these five changes and nothing else**. It closes the crash-#1
rawtx door (§2.1 door 2), the crash-#2 EMFILE fd-leak, and replaces the flat retry
loop with capped exponential backoff — three signatures at the orchestrator layer
in one file.

### The five changes

**1. New constants** (`error/bitcoind.js:80` and neighbours, with the other
`Bitcoin.DEFAULT_*`):

```js
Bitcoin.DEFAULT_START_RETRY_INTERVAL = 5000;   // base backoff: 5s, doubled each attempt
Bitcoin.DEFAULT_START_RETRY_COUNT = 10;        // was 60; with doubling, 10 tries spans ~13 min
Bitcoin.MAX_START_RETRY_INTERVAL = 160000;     // cap each backoff at 160s
Bitcoin.MIN_TX_BYTES = 10;                     // reject rawtx ZMQ frames smaller than this
Bitcoin.MAX_TX_BYTES = 2 * 1024 * 1024;        // ...or larger than 2 MB, before parsing
```

**2. `_zmqTransactionHandler` — size guard + try/catch** (the crash-#1 rawtx door),
`error/bitcoind.js:644-676`. Replaces the bare
`var tx = bitcore.Transaction(); tx.fromString(message);`:

```js
if (!Buffer.isBuffer(message) ||
    message.length < Bitcoin.MIN_TX_BYTES ||
    message.length > Bitcoin.MAX_TX_BYTES) {
  log.warn('_zmqTransactionHandler: rejecting rawtx frame, bad size: ' + ...);
  return;
}
var tx = bitcore.Transaction();
try {
  tx.fromString(message);
} catch (err) {
  log.warn('_zmqTransactionHandler: failed to parse rawtx, skipping: ' + (err.message || err));
  return;
}
```

**3. Two helpers — doubling backoff + unified retry**, `error/bitcoind.js:753-783`:

```js
Bitcoin.prototype._retryInterval = function(retryCount) {
  var ms = this.startRetryInterval * (1 << (retryCount - 1));   // left-shift, not Math.pow
  return Math.min(ms, Bitcoin.MAX_START_RETRY_INTERVAL);
};

Bitcoin.prototype._retryLoadTip = function(node, callback) {
  var self = this;
  var stopped = false;
  async.retry({ times: self.startRetryCount, interval: self._retryInterval.bind(self) },
    function(done) {
      if (self.node.stopping) { stopped = true; return done(); }
      self._loadTipFromNode(node, done);
    },
    function(err) {
      if (err) log.error('Failed to load tip from zerod after ' + self.startRetryCount +
        ' attempts, giving up: ' + (err.message || err));
      callback(err, stopped);
    });
};
```

**4. `_initZmqSubSocket` — fd-leak guard** (the EMFILE root cause),
`error/bitcoind.js:786`+, before `node.zmqSubSocket = zmq.socket('sub')`:

```js
if (node.zmqSubSocket) {
  try { node.zmqSubSocket.close(); }
  catch (e) { log.warn('ZMQ: error closing stale sub socket: ' + (e.message || e)); }
}
```

**5. `_spawnChildProcess` and `_connectProcess` both call `_retryLoadTip`**
(`error/bitcoind.js:970`, `error/bitcoind.js:1009`). The two inline
`async.retry({times, interval: self.startRetryInterval}, ...)` blocks are removed;
the RPC client is hoisted out, each site calls
`self._retryLoadTip(node, function(err, stopped) { ... })`. `_connectProcess` keeps
`rejectUnauthorized: _.isUndefined(config.rpcstrict) ? true : config.rpcstrict`.

### Reasoning (fix shapes)

- **Crash #1 has two doors, and `bitcoind.js` is the one nobody fixed.** Both the
  inv handler and `_zmqTransactionHandler` feed *untrusted* ZMQ bytes into the same
  parser. On toru the rawtx handler had no guard, so a malformed frame throws
  `RangeError` straight out of `tx.fromString` and kills the process regardless of
  the `index.js` fix. Change 2 mirrors the inv fix exactly — both doors shut, both
  log the same way.
- **The EMFILE leak is in bitcore, not zerod.** `_initZmqSubSocket` overwrote
  `node.zmqSubSocket` without closing the previous socket; under spawn-mode
  respawns the orphaned sub-socket fds accumulated until `EMFILE`. zerod is the ZMQ
  **PUB** and has nothing to close. Change 4 closes the stale socket before
  re-creating it. After the connect-mode cutover this path is dormant (no
  respawns), but the fix is correct and cheap, so it stays.
- **Live retry was fixed `5 s × 60`, not doubling** — five flat minutes of
  identical hammering, and `startRetryCount: 60` made the spawn-mode EMFILE spiral
  worse. Replaced with capped exponential backoff via a simple left-shift
  (`5, 10, 20, 40, 80, 160, 160, …` s, 10 attempts ≈ 13 min), a hard `log.error`
  and give-up at the end instead of silently looping.
- **No `bitcore.service` change needed.** The unit already has `Restart=on-failure`,
  `RestartSec=10`, `StartLimitIntervalSec=300`, `StartLimitBurst=5` (in `[Unit]`
  for systemd 237). The ~13-min in-process backoff means a zerod-unavailable
  situation is handled inside the process and never trips the 5-per-300s limit; the
  unit only enters `failed` on a genuine fast crash-loop. Cascading restarts flow
  via `PartOf=zerod.service`. (Unit details: [Insight.md](Insight.md) systemd
  section + `config/bitcore.service`.)

---

## 4. Crash #2 root cause — removed by the connect-mode cutover (live)

Crash #2's *mechanism* was spawn-mode: bitcore owning zerod's lifecycle. A stale
datadir lock ("Cannot obtain a lock... probably already running") made each `zerod`
spawn fail; the fixed-interval respawn loop (outside `async.retry`, so
`startRetryCount: 60` never bounded it) plus the `_initZmqSubSocket` fd-leak turned
one failure into fd exhaustion. The observed orphan state (toru, 2026-06-21): zerod
running detached (PPID 1) while bitcore was down — a bitcore restart then tried to
launch a *second* zerod against `/home/ubuntu/.zero`, collided on the lock, and
spiralled into EMFILE.

**This root cause is gone.** The cutover to `connect` mode under systemd is **live**
(executed 2026-06-22): systemd runs zerod, bitcore only connects to its RPC + ZMQ,
so there is no respawn loop, no spawn-time fd-leak path, and no stale-lock collision.
A bitcore restart now re-attaches to the still-running zerod instead of spawning a
rival. zerod surviving a bitcore crash is now *correct* — it is the stable thing
bitcore reconnects to.

The `error/bitcoind.js` fd-leak + backoff fixes (§3) are belt-and-suspenders for
this signature: the architectural change removes the trigger; the code change makes
the path safe even if it is ever exercised again.

The systemd unit coupling (`Requires`/`After`/`PartOf`), lock-file mechanics, and
crash-recovery runbook are in [Insight.md](Insight.md) Operations, with unit files in
`config/`. They are operations, not crash mitigations, so they live there.

---

## 5. The rest to merge (not yet staged)

| Item | Why deferred | Track as |
|---|---|---|
| **bn.js 2.0.4 → 5.2.3** in `bitcore-lib-zero/package.json` | A 3-major-version jump with changed API/behavior — unsafe as an in-place file swap. Needs `npm install` + bitcore-lib test suite + parse/sign smoke test. It is a security item (ReDoS-class), not a crash fix, so it does **not** block the crash deploy. | Its own test-gated change. Source/context: [InsightPort.md](InsightPort.md) §3, §5. |
| **In-process bad-frame rate counter** | The try/catch branches in `index.js`/`bitcoind.js` currently log every bad frame at `warn`. A counter (per-window) that escalates to a single `error` above a threshold turns "occasional malformed frame" into a signal without log-spam. Designed, not wired. | Add to the bad-frame branches when wiring observability (below). |

### Observability for the bad-frame branches (planned)

A single bad frame is noise; a *stream* is a buggy peer or an attacker probing the
parser. Three layers:

1. **In-process rate counter** (above) — `warn` below threshold, one `error` above.
2. **Attribution must come from zerod.** ZMQ strips the peer IP before the frame
   reaches bitcore, so the source is unknowable at this layer. Cross-reference
   `zero-cli getpeerinfo` and the `Misbehaving` lines in zerod's `debug.log`. A
   spike in bitcore bad-frame warns lined up against a misbehaving peer is the
   attribution.
3. **Banning** is a zerod action: `zero-cli setban <ip> add`. bitcore has no peer
   table to ban from.

---

## 6. Deploy / rollback (pointer)

Not deployed. When given the go-ahead, all three crash-#1 layers
(`index.js` + `bitcoind.js` + `transaction.js`) go **together** — `index.js` shuts
the inv door, `bitcoind.js` shuts the rawtx door, `transaction.js` makes both logs
diagnosable. `addresses.js` and `currency.js` are independent and can go
individually.

The exact stop/back-up/swap/start/verify procedure, the graceful-shutdown rules
(**never `kill -9` zerod** — always `zero-cli ... stop`; **never `rm` a lock**),
and the rollback path live in [Insight.md](Insight.md) Operations. Standing
constraint: nothing reaches toru without the user's explicit go-ahead.
