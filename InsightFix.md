# InsightFix — Crash signatures, mitigations, and deployed hardening

This document is the operational record of how the Zero Insight explorer
(`bitcore` process, Node v8.17.0) crashes in production, what each crash's log
signature looks like, and the fix in place for it. Each entry gives the signature,
when the bug was introduced and how often it fires, the root cause, and the *shape*
of the current fix with short snippets, pointing at the source file and line. The
fixes are in the code — a fresh `npm install` of the Zero `bitcore`/`insight`
packages carries them; no manual file surgery is needed.

**Source of truth for the crashes:** saved log tails of the `bitcore` process
dying. The captures, with when each crash was observed:

| Capture | Observed | Crash it documents |
|---|---|---|
| `rangeError.save` | 2022-09 | #1 tx-parser `RangeError` |
| `start2.tail` | 2022-09 | #1 (recurrence) |
| `start4.tail` | 2023-06 | #1 (recurrence) |
| `start5.tail` | 2024-05 | #4 expired-cert price feed |
| `start6.tail` | 2025-06 | #3 JS-heap OOM |
| `start11.tail` | 2026-06-20 | #2 EMFILE fd-leak |

---

## 1. The four production crash signatures (summary)

| # | Signature | First seen | Fatal? | Root cause | Fix (source file) |
|---|---|---|---|---|---|
| 1 | `RangeError: Index out of range` in tx parser | 2022-09 (recurs ×2 2022-09, 2023-06; absent 2024–2026) | Yes — kills process | Malformed/truncated tx buffer off the ZMQ `rawtx` topic makes `Transaction.fromBuffer` read past the end; the throw is uncaught in the event handler. **Two doors** (inv path + rawtx path). | `insight-api-zero/lib/index.js`, `bitcore-node-zero/lib/services/bitcoind.js`, `bitcore-lib-zero/lib/transaction/transaction.js` |
| 2 | `Error: EMFILE: too many open files` | 2026-06-20 | Yes | Stale datadir lock → ~5 s restart loop leaks ZMQ sockets/fds until `ulimit -n`. `startRetryCount: 60` made it worse. | Two-fold: root cause removed by running in connect mode (zerod owned by systemd, no respawn loop); fd-leak + backoff hardened in `bitcore-node-zero/lib/services/bitcoind.js` |
| 3 | `FATAL ERROR: ... JS heap out of memory` (abort + core) | 2025-06 | Yes | One Express `response.send()` builds a ~163 MB string (163144806 bytes, `response.js:107`) — oversized unpaginated API response — past the ~1.4 GB Node-8 heap. | `insight-api-zero/lib/addresses.js` (caps 100k/100k, 50 MB ceiling) |
| 4 | `Error: certificate has expired` | 2024-05 (repeats ~10 min) | No — kept serving | Outbound price-feed TLS fails under Node 8.17's stale bundled CA roots. | `insight-api-zero/lib/currency.js` |

The Node-8 / OpenSSL-1.0.2 constraint behind #4 (and the upgrade wall) is documented
in [InsightPort.md](InsightPort.md) §2. The lock-file mechanics behind #2 are in
[InsightBlock.md §5.2](InsightBlock.md#52-lock-files). Those are not repeated here.

**Not a crash:** a UI cosmetic fix — the offline banner inherited "zcashd" text from
the str4d Zcash Insight fork and now reads "zerod" — lives in §4a, not this table.

---

## 2. The backend fixes (by source file)

The hardening lives in five backend files across the Zero packages. Three of them
(`index.js`, `bitcoind.js`, `transaction.js`) together close crash #1;
`addresses.js` closes #3; `currency.js` closes #4. `bitcoind.js` additionally
carries the #2 fd-leak/backoff work (consolidated in §3 below).

| Source file | Closes |
|---|---|
| `insight-api-zero/lib/index.js` | #1 inv door |
| `bitcore-node-zero/lib/services/bitcoind.js` | #1 rawtx door, #2 fd-leak/backoff |
| `bitcore-lib-zero/lib/transaction/transaction.js` | #1 diagnostic context |
| `insight-api-zero/lib/addresses.js` | #3 OOM |
| `insight-api-zero/lib/currency.js` | #4 cert |

The UI banner fix (§4a) is one template:

| Source file | Closes |
|---|---|
| `insight-ui-zero/public/views/includes/connection.html` | §4a banner text + `translate` directive removal |

The banner fix needs no catalog or bundle change — see §4a for why.

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

- **Door 1 — inv path** (`insight-api-zero/lib/index.js`): constants
  `InsightAPI.MIN_TX_BYTES = 10` / `MAX_TX_BYTES = 2 MB` (`index.js:294`), guard +
  try/catch in `transactionEventHandler` (`index.js:297-320`). Logger is reached as
  `this.node.log` (there is no top-level `log` in that file; inside the handler
  `this` is the InsightAPI instance):

  ```js
  // insight-api-zero/lib/index.js — transactionEventHandler
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

- **Door 2 — rawtx path** (`bitcore-node-zero/lib/services/bitcoind.js`,
  `_zmqTransactionHandler`). The originally-unguarded door — it parses every rawtx
  ZMQ frame via `tx.fromString(message)` with no size check and no try/catch, so the
  same `RangeError` kills the process independently of the inv fix. Mirrors door 1
  (full detail in §3): frame-size guard at `bitcoind.js:662`, parse try/catch at
  `bitcoind.js:674`.

- **Door 3 — diagnostic context** (`bitcore-lib-zero/lib/transaction/transaction.js`):
  re-throws the bare `RangeError` with context (buffer length + parsed version) so
  the cause is identifiable in logs. Not required to stop the crash (the two handler
  try/catches do that), but it makes both doors' logs diagnosable.

**Design note — `warn`, not `error`.** A malformed ZMQ frame is *expected*
untrusted input and the process recovers fully by dropping it — that is the
definition of `warn`. `error` is reserved for "the node is broken." This crash is
local hardening, not a port from any sibling project.

### 2.2 Crash #3 — JS-heap OOM from an oversized response

**Symptom.** From `start6.tail` (2025-06): `FATAL ERROR: ... JS heap out of memory`,
abort + core dump. One Express `response.send()` built a ~163 MB string
(163144806 bytes, `response.js:107`) on a ~1.4 GB Node-8 heap. Culprit: an
unpaginated API response — most likely `addr/:addr` returning the full `txList`
when `from`/`to` are omitted, or an unbounded `utxo`/`multiutxo` array.

**Fix shape — bound the response before serializing.** In
`insight-api-zero/lib/addresses.js`:

- A `sendChecked(self, res, data)` helper (`addresses.js:28`) that
  `JSON.stringify`s the body *inside try/catch* (a serialization throw becomes a
  handled error, not a crash), enforces `MAX_RESPONSE_BYTES = 50 MB`
  (`addresses.js:22`) → `413 jsonp` when exceeded (`addresses.js:38-39`),
  then sends. A clean `413` instead of allocating hundreds of MB and aborting.
  Applied to `show`, `utxo`, `multiutxo`, `multitxs`
  (`addresses.js:68,191,209,262`).

  ```js
  // addresses.js — sendChecked (shape)
  var body;
  try { body = JSON.stringify(data); }
  catch (e) { return res.status(500).jsonp({ error: 'serialization failed' }); }
  if (body.length > MAX_RESPONSE_BYTES) {
    return res.status(413).jsonp({ error: 'Response too large; use pagination (from/to or pageNum).' });
  }
  res.set('Content-Type', 'application/json').send(body);
  ```

- The address summary's txid list is capped at `MAX_TXIDS = 100000`
  (`addresses.js:23,111-114`) with `txAppearancesTruncated` /
  `txAppearancesLimit` flags (`addresses.js:130-132`) so callers know to page;
  utxo arrays are rejected with a `413` past `MAX_UTXOS = 100000`
  (`addresses.js:24,186-190,204-208`).

**Cap values.** The count caps sit at `100000`/`100000`, raised from an earlier
`10000`/`50000` after live measurement (the higher cap serves the common-large
"whale" class whole — see sizing, below). `MAX_RESPONSE_BYTES`
(50 MB) is the real OOM guard and is unchanged; the count caps are a cheap early-out
so we never even build arrays we already know are too big.

| Constant | Value (deployed) | Role |
|---|---|---|
| `MAX_RESPONSE_BYTES` | 50 MB | Hard OOM backstop. Serialize, measure, `413` if body > 50 MB. Catches any response by serialized size regardless of element count. |
| `MAX_TXIDS` | 100,000 | Truncate the summary txid list; set `txAppearancesTruncated` + `txAppearancesLimit`. |
| `MAX_UTXOS` | 100,000 | `413` if a `/utxo` array exceeds this count. |

**Sizing — what the real worst case looks like.** A small set of **high-volume
addresses** appear in a slice of nearly every block's coinbase, so their
tx-appearance and UTXO counts dwarf any ordinary address and define the worst-case
load for `/utxo`. Measured against the deployed caps:

| Class | txAppearances | UTXOs | `/utxo` result |
|---|---:|---:|---|
| drained high-volume addr | ~389k | 0 | 200 (empty set) |
| ~512k-UTXO mega-address | ~800k | ~512k | **413** (~135 MB if served whole) |
| ~800k-UTXO mega-address | ~800k | ~800k | **413** (~210 MB → **would OOM** if served whole) |
| ~80k-UTXO addr (calibration) | ~80k | ~80k | 200 (~20.7 MB) — served whole |

(Specific addresses are intentionally omitted; the figures above are generalized to
the size classes that matter for the caps.)

**How the 100k cap maps to bytes.** A single serialized `/utxo` element
(`transformUtxo`: address, txid, vout, scriptPubKey hex, amount, satoshis, height,
confirmations) is **≈ 260–280 B** — the empirical unit rate. Two anchors hold this:

- *Measured:* the ~80k-UTXO calibration address returned a full **~20.7 MB** body
  (200). That back-solves to 20.7 MB ÷ ~80k ≈ **273 B/UTXO**, squarely in the
  260–280 B band.
- *Calculated:* at the `MAX_UTXOS = 100,000` cap, 100k × 260–280 B ≈ **26–38 MB** — the
  full range, still under the 50 MB ceiling with margin. (The `addresses.js` source
  comment currently rounds the calibration body to "~30 MB" and cites only the 38 MB
  top of the range; the measured figure is 20.7 MB.)

So 100k is the largest count cap that *cannot* breach the byte ceiling even at the
280 B upper bound, while still serving the common-large whale class whole. By
contrast an ~800k-UTXO address served whole (~210 MB ≈ 800k × 263 B) is exactly the
crash-#3 abort. **Decision: keep caps at 100k.** Do NOT raise them to serve the
mega-addresses in full — that re-introduces the OOM we just closed. Note the cap
currently rejects only *after* the node returns the full UTXO set, so the 413 path is
slow on the mega-addresses (the upstream fetch cost remains); a pre-count /
pagination is the durable fix. These high-volume addresses are
**known mega-addresses** — a `/utxo` 413 on them is expected, not a regression.

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

**Fix shape — trust the OS CA bundle, degrade gracefully.** In
`insight-api-zero/lib/currency.js`:

- **CA trust (the actual handshake fix):** load the OS CA bundle once at module
  load from `CA_CANDIDATES` (`/etc/ssl/certs/ca-certificates.crt`,
  `/etc/pki/tls/certs/ca-bundle.crt`) into `SYSTEM_CA` (`currency.js:32`),
  and pass it as `ca` on each request via `requestOpts(url)`
  (`currency.js:45-46`). Falls back to Node's default trust if absent.
  `rejectUnauthorized` is **left on** — this fixes verification, it does not
  disable it.

  ```js
  // currency.js — module load
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

## 3. `bitcoind.js` hardening — consolidated (three signatures, one file)

`bitcore-node-zero/lib/services/bitcoind.js` carries five changes that together
close the crash-#1 rawtx door (§2.1 door 2), the crash-#2 EMFILE fd-leak, and
replace the flat retry loop with capped exponential backoff — three signatures at
the orchestrator layer in one file. (Line numbers below use the short basename
`bitcoind.js`.)

### The five changes

**1. New constants** (`bitcoind.js:80` and neighbours, with the other
`Bitcoin.DEFAULT_*`):

```js
Bitcoin.DEFAULT_START_RETRY_INTERVAL = 5000;   // base backoff: 5s, doubled each attempt
Bitcoin.DEFAULT_START_RETRY_COUNT = 10;        // was 60; with doubling, 10 tries spans ~13 min
Bitcoin.MAX_START_RETRY_INTERVAL = 160000;     // cap each backoff at 160s
Bitcoin.MIN_TX_BYTES = 10;                     // reject rawtx ZMQ frames smaller than this
Bitcoin.MAX_TX_BYTES = 2 * 1024 * 1024;        // ...or larger than 2 MB, before parsing
```

**2. `_zmqTransactionHandler` — size guard + try/catch** (the crash-#1 rawtx door),
`bitcoind.js:644-676`. Replaces the bare
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

**3. Two helpers — doubling backoff + unified retry**, `bitcoind.js:753-783`:

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
`bitcoind.js:786`+, before `node.zmqSubSocket = zmq.socket('sub')`:

```js
if (node.zmqSubSocket) {
  try { node.zmqSubSocket.close(); }
  catch (e) { log.warn('ZMQ: error closing stale sub socket: ' + (e.message || e)); }
}
```

**5. `_spawnChildProcess` and `_connectProcess` both call `_retryLoadTip`**
(`bitcoind.js:970`, `bitcoind.js:1009`). The two inline
`async.retry({times, interval: self.startRetryInterval}, ...)` blocks are removed;
the RPC client is hoisted out, each site calls
`self._retryLoadTip(node, function(err, stopped) { ... })`. `_connectProcess` keeps
`rejectUnauthorized: _.isUndefined(config.rpcstrict) ? true : config.rpcstrict`.

### Reasoning (fix shapes)

- **Crash #1 has two doors, and `bitcoind.js` is the one nobody fixed.** Both the
  inv handler and `_zmqTransactionHandler` feed *untrusted* ZMQ bytes into the same
  parser. The rawtx handler had no guard, so a malformed frame throws
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
  via `PartOf=zerod.service`. (Unit details: [InsightBlock.md §4.2](InsightBlock.md#42-systemd-model)
  + `config/bitcore.service`.)

---

## 4. Crash #2 root cause — removed by running in connect mode

Crash #2's *mechanism* is spawn-mode: bitcore owning zerod's lifecycle. A stale
datadir lock ("Cannot obtain a lock... probably already running") makes each `zerod`
spawn fail; the fixed-interval respawn loop (outside `async.retry`, so
`startRetryCount: 60` never bounded it) plus the `_initZmqSubSocket` fd-leak turn
one failure into fd exhaustion. The failure mode: zerod left running detached
(PPID 1) while bitcore is down — a bitcore restart then tries to launch a *second*
zerod against the datadir, collides on the lock, and spirals into EMFILE.

**In connect mode this root cause is gone:** systemd runs zerod, bitcore only
connects to its RPC + ZMQ, so there is no respawn loop, no spawn-time fd-leak path,
and no stale-lock collision. A bitcore restart re-attaches to the still-running
zerod instead of spawning a rival. zerod surviving a bitcore crash is *correct* — it
is the stable thing bitcore reconnects to.

The `bitcore-node-zero/lib/services/bitcoind.js` fd-leak + backoff fixes (§3) are belt-and-suspenders for
this signature: the architectural change removes the trigger; the code change makes
the path safe even if it is ever exercised again.

The systemd unit coupling (`Requires`/`After`/`PartOf`), lock-file mechanics, and
crash-recovery runbook are in [InsightBlock.md §5](InsightBlock.md#5-recovery), with unit files in
`config/`. They are operations, not crash mitigations, so they live there.

---

## 4a. UI banner — "zcashd" → "zerod"

The red offline banner inherited from str4d's Zcash Insight fork read *"Can't
connect to zcashd…"*. This explorer fronts **zerod**, so it is wrong; corrected to
*"Can't connect to zerod to get live updates"*.

The banner used angular-gettext's `translate` directive (English source text = catalog
lookup key), but there are no zerod translations. The fix **removes the directive**
and edits the text — the `<p>` renders its literal English in every locale. This
touches only `connection.html`; the catalog (`translations.js` / `main.min.js`) is
not in play and needs no edit or rebuild.

| File | Change | Bytes |
|---|---|---|
| `views/includes/connection.html` | `!apiOnline` `<p>`: text → "Can't connect to zerod to get live updates", `translate` removed | 711 → 626 |

**Serving.** Static template — no service restart. Served under the `/insight/` prefix
(`/insight/views/includes/connection.html`); fetched live, so a browser Shift-reload
picks it up.

### Message / translation tests (how to verify)

The banner only renders when the gate is tripped, and the connection is normally
healthy, so verification is done by **forcing the banner** without disturbing zerod:

1. **Render the banner (no node interference).** In the browser DevTools console on
   the live site:

   ```js
   angular.element(document.querySelector('.connection-status'))
     .scope().$apply(function(s){ s.apiOnline = false; });
   ```

   The red `alert-danger` box appears (it renders when `!apiOnline || !serverOnline
   || !clienteOnline`). Confirm the text reads "Can't connect to zerod to get live
   updates" — no "zcashd". DevTools Network → **Offline** is the alternative trigger.

2. **Locale-independence.** Use the footer language dropdown
   (Deutsch / Español / 日本語); each must show the **same English** sentence — the
   directive is gone, so there is no per-locale lookup and the literal renders in
   every language. `setLanguage` clears `$templateCache` and `$route.reload()`, so no
   manual refresh is needed.

3. **Served-bytes check (deploy proof).** Confirm the public site serves the edited
   template, not a stale copy, by md5-matching served ↔ local at the `/insight/`
   prefix:

   ```sh
   curl -sL https://insight.zeromachine.io/insight/views/includes/connection.html | md5sum
   ```

   Expected: connection.html `58094a9afafd6d9dfed2d3c71493caf8` (matches
   `insight-ui-zero/public/views/includes/connection.html`). Also confirm the
   served template carries no `translate` attribute on the `!apiOnline` `<p>` and no
   "zcashd".

### Flushing caches after a static deploy

This applies to **static assets only** — `custom.css`, the `views/*.html` templates,
images — served by `express.static`, which reads from disk per request and holds no
content cache. A `bitcore` restart has **no** effect on what a client sees for these;
the gate is the caches in front. (Backend `.js` changes are the opposite case:
`express.static` does not apply, the file is loaded into the running Node process at
startup, so a `bitcore` restart — `systemctl restart bitcore.service` if running under
systemd — **is** required for the change to take effect, and no cache-flush is
involved.)

For a static asset, a served-bytes check (above) that still returns the old md5 after
the file on disk has changed means a cache layer in front is serving a stale copy.
Flush each caching layer the request passes through, front to back, then hard-reload
the browser; the served-bytes check should then match the on-disk file.

- **Reverse proxy (nginx).** Only if a `proxy_cache` is configured (the sample vhost
  in [`config/nginx-default`](config/nginx-default) configures none, so nothing to
  flush there). If one is added later, purge its cache zone or `systemctl reload
  nginx` per that config.
- **CDN / edge.** If the site is fronted by a CDN (e.g. Cloudflare, or another
  provider), the edge caches static assets and may apply its own TTL regardless of the
  origin `Cache-Control`. **Purge the CDN edge cache after every static deploy** —
  via the provider's dashboard or API — or the edge serves the stale asset until its
  TTL expires. This is the layer that most often masks a deploy.
- **Browser.** Force a cache-bypassing reload of the page so the browser re-fetches
  the asset instead of serving its own cached copy. In Chrome: **Ctrl+Shift+R** on
  Windows, **Ctrl+Shift+R** on Linux, **Cmd+Shift+R** on macOS. (DevTools open →
  right-click reload → "Empty Cache and Hard Reload" is the exhaustive variant.)

Re-run the served-bytes md5 check after flushing; a match confirms the deploy is live
end to end.

---

## 5. Deploy / rollback (pointer)

Deploying these fixes (the supported path: update the explorer packages and
revalidate) is [InsightBlock.md §5.7](InsightBlock.md#57-deploying-updated-explorer-packages).
The graceful-shutdown rules (**never `kill -9` zerod** — always `zero-cli ... stop`,
since SIGKILL forces a multi-hour dirty-shutdown reindex; **never `rm` a lock** —
fd-locks are kernel-owned), the backup convention, and the rollback path live in
[InsightBlock.md §5](InsightBlock.md#5-recovery).

---

## 6. Monitoring — verifying the fixes hold

Each fix has a cheap health check. Run these from the host; the service runs as
`bitcore.service` under systemd in **connect** mode. (Set the journal window to your
deploy date or a recent span, e.g. `--since '-7d'`.)

**Service health (covers #1, #2, #3 — any of them kills or restarts the process).**

```sh
systemctl status bitcore.service --no-pager        # active, NRestarts low/stable
systemctl show bitcore.service -p NRestarts         # 0 since deploy = no crash-loop
journalctl -u bitcore.service --since '<deploy-date>' \
  | grep -Ei 'heap|OOM|RangeError|EMFILE|FATAL'     # expect: nothing
```

A clean `NRestarts=0` since the deploy is the headline signal: it means none of
crashes #1/#2/#3 have fired.

**Crash #1 (bad-frame doors).** The fix logs-and-drops instead of crashing. A bad
frame appears as a `warn`, not a process death:

```sh
journalctl -u bitcore.service --since '<deploy-date>' \
  | grep -E 'rejecting (inv|rawtx)|failed to parse'
```

Occasional lines = the guard working. A *stream* of them = a buggy/abusive peer —
cross-reference `zero-cli getpeerinfo` and `Misbehaving` in zerod's `debug.log` for
attribution (ZMQ strips the peer IP before bitcore sees the frame). Ban from zerod,
not bitcore: `zero-cli setban <ip> add`.

**Crash #3 (oversized response).** Confirm the caps fire on a high-volume
mega-address with a clean `413`, not an abort (substitute a known mega-address):

```sh
curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' \
  https://insight.zeromachine.io/insight-api-zero/addr/<MEGA_ADDR>/utxo
# expect 413 on an ~800k-UTXO mega-address; the ~80k-UTXO address returns 200 ~20.7 MB
```

**Crash #4 (price feed).** Non-fatal; the explorer keeps serving last-known rates.
Health = the feed is refreshing, not erroring every ~10 min:

```sh
journalctl -u bitcore.service --since '<deploy-date>' | grep -Ei 'certificate|currency'
# expect: no 'certificate has expired'
```

The front-page price ticker showing a live USD/BTC value is the user-visible proof.

**UI banner (§4a).** Message / translation tests are in §4a — DevTools `$apply` to
force the banner, footer language switch for fall-through, and the served-bytes md5
check at the `/insight/` prefix.

**`node --check` runtime caveat.** Any `node --check` of a staged file must run
under the **service's** v8.17.0, not a bare `node` (which may resolve to a different
version depending on shell/PATH). Use the explicit nvm path to the v8.17.0 binary.

---

## 7. Known issue — residual `zcashd` strings in `bitcoind.js`

`bitcore-node-zero/lib/services/bitcoind.js` carries inherited `zcashd` strings from
the str4d Zcash lineage. Line 876 is a functional bug; the rest are message text.

| Line | Text | Kind |
|---|---|---|
| **876** | `var pidPath = spawnOptions.datadir + '/zcashd.pid'` | **filesystem path — bug** |
| 345-347 | `'...in zcashd config options'` (×3 checkArgument) | error string |
| 431 | `'...zcashd is undergoing a reindex.'` | log warn |
| 976 | `'Stopping while trying to spawn zcashd.'` | error string |
| 1015 | `'Stopping while trying to connect to zcashd.'` | error string |
| 2253 | `'zcashd spawned process exited with status code: '` | error string |
| 2265 | `'zcashd process did not exit'` | error string |

**Line 876 — wrong pidfile name in the spawn-mode orphan reaper.** `_stopSpawnedBitcoin`
reads `pidPath` to find and `SIGINT` a zerod that a prior spawn left orphaned in the
datadir, before launching a new one. It targets `zcashd.pid`, but the Zero daemon
writes `zerod.pid`, so the read hits `ENOENT` and the function treats it as "no orphan,
continue" — silently failing to reap a genuinely orphaned zerod, the path to the #2
EMFILE/datadir-lock failure. It is spawn-mode-only, so the live **connect** deployment
never executes it; but spawn is a supported deployment choice, so for a spawn-mode
install this is an active bug, not dormant. Fix is a one-line retarget:

```js
var pidPath = spawnOptions.datadir + '/zerod.pid';
```

This is the portable fix (`fs.readFile` + `process.kill` work on any Node host,
including non-Linux). A Linux-only reaper keyed on the datadir lock-holder
(`lsof ~/.zero/.lock`) + process parentage would be more robust where available, but
must not replace the portable pidfile path for cross-platform spawn installs.

Behavioral change → code review + `bitcoind.js` redeploy, validated in a spawn-mode
window (connect mode never exercises this path). The remaining lines are user-facing
message text; safe to retarget `zcashd`→`zerod` in the same revision.
