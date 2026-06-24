# InsightDeploy — Step-by-step deploy & validation of the five staged fixes

Operational runbook for promoting the five hardened files in
[`error/`](error/) into the live `node_modules` tree on the explorer host
(`HOST`, reached via `ssh HOST`). Companion to
[InsightFix.md](InsightFix.md) (what each fix is and why) and
[InsightBlock.md](InsightBlock.md) §4–5 (operations / recovery, the source of
truth for the systemd and shutdown rules referenced below).

**Standing constraint:** nothing here runs without explicit go-ahead. Each file
swap is reversible from a per-file `.deploy.bak` taken at swap time; the stack is
live in **connect** mode (zerod owned by systemd, bitcore only reconnects), so a
bitcore restart re-attaches to the running zerod and never disturbs the chain.

---

## 0. Host facts (verified 2026-06-23)

| Fact | Value |
|---|---|
| Host | `HOST` (the explorer host; run these commands on it) |
| Staged copies | `/home/ubuntu/zero/insight/error/<file>` (repo clone @ `eeee7ec`) |
| Deploy root | `/home/ubuntu/zero/mynode/node_modules/` |
| Service node | **`/home/ubuntu/.nvm/versions/node/v8.17.0/bin/node`** (from `bitcore.service` `ExecStart`) |
| ⚠ default-PATH node | `v8.10.0` — **do not** use it for `node --check`; pin v8.17.0 |
| Mode | `connect` (live); rollback config `bitcore-node.json.spawn.bak` present |
| Services | `zerod.service` active, `bitcore.service` active |

**The five files and the repo each one lands in:**

| # | Staged (`error/`) | Deploy target under `node_modules/` | Repo affected | Closes |
|---|---|---|---|---|
| A | `index.js` | `insight-api-zero/lib/index.js` | **insight-api-zero** | #1 inv door |
| B | `bitcoind.js` | `bitcore-node-zero/lib/services/bitcoind.js` | **bitcore-node-zero** | #1 rawtx door, #2 fd-leak/backoff |
| C | `transaction.js` | `bitcore-lib-zero/lib/transaction/transaction.js` | **bitcore-lib-zero** | #1 diagnostic context |
| D | `addresses.js` | `insight-api-zero/lib/addresses.js` | **insight-api-zero** | #3 OOM |
| E | `currency.js` | `insight-api-zero/lib/currency.js` | **insight-api-zero** | #4 expired cert |

Current staged-vs-deployed diff sizes (sanity that the swaps are real and bounded):
A +28/−1, B +89/−32, C +15/−1, D +56/−5, E +76/−26.

---

## 1. Prioritization & grouping

Group by **blast radius and coupling**, not by file. Three groups, deploy in this
order; each group is independently validated and independently reversible.

### Group 1 — Crash #1, the RangeError (A + B + C, deploy together)

**Priority: highest. Must go as one unit.** Crash #1 has *two doors* into the same
parser and a third file that only adds log context:

- **A** `index.js` shuts the **inv** door (insight-api-zero).
- **B** `bitcoind.js` shuts the **rawtx** door (bitcore-node-zero) — the one nobody
  had fixed — *and* carries the #2 EMFILE fd-leak guard + exponential-backoff retry.
- **C** `transaction.js` (bitcore-lib-zero) re-throws the bare `RangeError` with
  buffer length + version so both doors' logs are diagnosable.

Deploying only one door leaves the process killable through the other. Deploy A, B,
C, then a single bitcore restart, then validate as a set. This group touches all
**three** repos and is the one with real behavioral change (parser guards, retry
loop, socket lifecycle), so it gets the most validation.

> B also resolves crash #2 belt-and-suspenders. The #2 *root cause* (spawn-mode
> respawn loop) is already gone via the connect-mode cutover (InsightFix.md §4), so
> B's fd-leak path is dormant in production — but the guard is correct and cheap.

### Group 2 — Crash #3, the OOM (D, independent)

**Priority: high, independent.** `addresses.js` bounds oversized address responses
(`sendChecked` 50 MB cap → `413`, txid list capped at 100,000). Touches only
**insight-api-zero**, no coupling to Group 1. A real, user-reachable fix (an
attacker or a whale address can still OOM the box today), so deploy soon — but it
can ride separately and be validated on its own with a big-address curl.

### Group 3 — Crash #4, the expired cert (E, independent, lowest urgency)

**Priority: low, independent.** `currency.js` is the only **non-fatal** signature —
the explorer keeps serving; only the outbound CoinGecko price fetch fails. Loads the
OS CA bundle, degrades gracefully, fixes the cold-start `usd/btc` init. Touches only
**insight-api-zero**. Deploy last; validation is "price refreshes without the
~10-min cert-expired warn."

**Recommended sequence:** Group 1 first (and as a unit) → Group 2 → Group 3. If you
want the smallest first step, Group 3 alone is the lowest-risk single swap to
rehearse the procedure on; but by *impact* Group 1 leads.

---

## 2. Pre-flight (once, before any swap)

Run read-only; nothing here changes the live tree.

```sh
ERR=/home/ubuntu/zero/insight/error
NM=/home/ubuntu/zero/mynode/node_modules
NODE=/home/ubuntu/.nvm/versions/node/v8.17.0/bin/node

# 2.1 staged files parse clean under the SERVICE node (not default PATH node)
for f in index.js bitcoind.js transaction.js addresses.js currency.js; do
  "$NODE" --check "$ERR/$f" && echo "check OK: $f"
done

# 2.2 re-confirm each diff is exactly the intended change set (eyeball it)
diff -u "$NM/bitcore-node-zero/lib/services/bitcoind.js" "$ERR/bitcoind.js" | less
#   ...repeat per file/target from the table in §0...

# 2.3 capture a known-good baseline to compare against after deploy
curl -s http://127.0.0.1:3001/insight-api-zero/sync; echo
systemctl is-active zerod bitcore
pgrep -x zerod | wc -l            # must be exactly 1
grep -E "connect|spawn" ~/zero/mynode/bitcore-node.json
```

Gate: all five `--check OK`, every diff is only the documented changes, baseline
`sync` returns the live tip, exactly one zerod in connect mode. Do not proceed past a
failure.

---

## 3. Deploy — Group 1 (A + B + C)

Per-file: back up the live original to a timestamped `.deploy.bak`, copy the staged
file in, verify it parses *in place* under the service node. Then one restart for the
whole group.

```sh
set -e
ERR=/home/ubuntu/zero/insight/error
NM=/home/ubuntu/zero/mynode/node_modules
NODE=/home/ubuntu/.nvm/versions/node/v8.17.0/bin/node
TS=$(date +%Y%m%d-%H%M%S)

swap() {  # $1 = staged name, $2 = target path under node_modules
  cp -p "$NM/$2" "$NM/$2.deploy.bak.$TS"
  cp "$ERR/$1" "$NM/$2"
  "$NODE" --check "$NM/$2" && echo "deployed+check OK: $2"
}
swap index.js       insight-api-zero/lib/index.js
swap bitcoind.js    bitcore-node-zero/lib/services/bitcoind.js
swap transaction.js bitcore-lib-zero/lib/transaction/transaction.js

# one restart for the group — reconnects to the running zerod, chain stays up
sudo systemctl restart bitcore.service
```

`bitcore-lib-zero` (C) and `insight-api-zero` (A) are loaded into the bitcore
process, so a single `systemctl restart bitcore` picks up all three. No zerod
restart — connect mode means zerod is untouched.

---

## 4. Validate — Group 1

```sh
systemctl is-active bitcore                                   # active
sleep 3
curl -s http://127.0.0.1:3001/insight-api-zero/sync; echo     # live tip, status synced
curl -s "http://127.0.0.1:3001/insight-api-zero/status?q=getInfo"; echo
pgrep -x zerod | wc -l                                        # still exactly 1
# clean startup, no parser/throw on boot, no EMFILE:
journalctl -u bitcore -b --no-pager | tail -n 40
journalctl -u bitcore -b --no-pager | grep -iE "RangeError|EMFILE|uncaught" || echo "no crash signatures"
```

Pass criteria:
- `bitcore` active; `sync` returns the advancing live height; `getInfo` answers.
- Exactly one zerod, still connect mode.
- No `RangeError` / `EMFILE` / `uncaught` in this boot's log; the bad-frame guards
  log at **`warn`** (expected, harmless) if a malformed frame arrives.
- Tip keeps advancing over a few minutes (the rawtx/inv handlers still process good
  frames — guards reject only bad ones).

Let it run and watch for one block interval before calling Group 1 done.

---

## 5. Deploy + validate — Group 2 (D, addresses.js → insight-api-zero)

```sh
set -e
ERR=/home/ubuntu/zero/insight/error
NM=/home/ubuntu/zero/mynode/node_modules
NODE=/home/ubuntu/.nvm/versions/node/v8.17.0/bin/node; TS=$(date +%Y%m%d-%H%M%S)
cp -p "$NM/insight-api-zero/lib/addresses.js" "$NM/insight-api-zero/lib/addresses.js.deploy.bak.$TS"
cp "$ERR/addresses.js" "$NM/insight-api-zero/lib/addresses.js"
"$NODE" --check "$NM/insight-api-zero/lib/addresses.js" && echo "deployed+check OK: addresses.js"
sudo systemctl restart bitcore.service

# validate: a normal address still returns; pagination flags appear; no OOM
systemctl is-active bitcore
curl -s "http://127.0.0.1:3001/insight-api-zero/addr/<KNOWN_ADDR>?noTxList=1"; echo
# a high-volume address should now page / cap rather than build a 100+MB body:
curl -s -o /dev/null -w "%{http_code} %{size_download}\n" \
  "http://127.0.0.1:3001/insight-api-zero/addr/<BIG_ADDR>"
journalctl -u bitcore -b --no-pager | grep -iE "heap|out of memory" || echo "no OOM"
```

Pass: normal address unchanged; a huge address returns `200` with a bounded body (or
`413` past 50 MB) instead of aborting; no heap-OOM in the log.

---

## 6. Deploy + validate — Group 3 (E, currency.js → insight-api-zero)

```sh
set -e
ERR=/home/ubuntu/zero/insight/error
NM=/home/ubuntu/zero/mynode/node_modules
NODE=/home/ubuntu/.nvm/versions/node/v8.17.0/bin/node; TS=$(date +%Y%m%d-%H%M%S)
cp -p "$NM/insight-api-zero/lib/currency.js" "$NM/insight-api-zero/lib/currency.js.deploy.bak.$TS"
cp "$ERR/currency.js" "$NM/insight-api-zero/lib/currency.js"
"$NODE" --check "$NM/insight-api-zero/lib/currency.js" && echo "deployed+check OK: currency.js"
sudo systemctl restart bitcore.service

# validate: price endpoint returns a non-zero rate; no recurring cert-expired warn
systemctl is-active bitcore
curl -s "http://127.0.0.1:3001/insight-api-zero/currency"; echo
sleep 60
journalctl -u bitcore --since "2 min ago" --no-pager | grep -iE "certificate has expired" \
  && echo "STILL FAILING — investigate CA bundle path" || echo "no cert-expired warn"
```

Pass: `/currency` returns live `usd`/`btc`; no `certificate has expired` in the
window. If the OS CA bundle path differs on this host, the fetch still degrades
gracefully (serves last-known) — that is acceptable, but note it.

---

## 7. Rollback

Reversible at two granularities. **Connect mode means none of this touches zerod or
the datadir** — only the bitcore process and its loaded files.

### 7.1 Per-file (preferred — undo one swap)

Each swap left a `.deploy.bak.<TS>` beside the target. To revert one file:

```sh
NM=/home/ubuntu/zero/mynode/node_modules
NODE=/home/ubuntu/.nvm/versions/node/v8.17.0/bin/node
# pick the target + its newest backup, e.g. bitcoind.js:
T=bitcore-node-zero/lib/services/bitcoind.js
B=$(ls -t "$NM/$T.deploy.bak."* | head -1)
cp "$B" "$NM/$T" && "$NODE" --check "$NM/$T" && echo "reverted: $T"
sudo systemctl restart bitcore.service
```

Group 1 must be rolled back **as a set** (A+B+C together) for the same reason it
deploys as a set — reverting one door re-opens the crash through the other. Groups 2
and 3 revert individually.

### 7.2 Whole-stack mode rollback (last resort)

If the explorer behaves wrong in a way a file revert doesn't fix, fall back to
**spawn mode** per [InsightBlock.md §5.4](InsightBlock.md#54-rolling-back-to-spawn-mode):

```sh
sudo systemctl disable --now bitcore zerod
/home/ubuntu/zero/BIN/zero-cli -datadir=/home/ubuntu/.zero stop 2>/dev/null; sleep 5
cd /home/ubuntu/zero/mynode && cp bitcore-node.json.spawn.bak bitcore-node.json
./bitcore_start.sh > start.out 2>&1 &
```

This is mode rollback, not file rollback — only reach for it if connect mode itself
is the problem. The units are additive and the datadir is never modified, so it
returns the exact prior state.

---

## 8. Recovery (if a deploy crashes the process)

Follow [InsightBlock.md §5](InsightBlock.md#5-recovery). The fast path:

```sh
journalctl -u bitcore -b --no-pager | tail -n 80   # read the signature
# match it against InsightFix.md, then per-file revert (§7.1) the file you just swapped
```

Hard rules carried from InsightBlock.md, do not violate:

- **Never `kill -9` zerod** — graceful stop only (`systemctl stop` / `zero-cli stop`);
  SIGKILL forces a multi-hour dirty-shutdown reindex.
- **Never `rm` a lock** — fd-locks are kernel-owned; identify the holder with `lsof`,
  stop it gracefully, confirm gone, then start (§5.2).
- A transient bitcore restart right after deploy (losing the RPC-ready race, §3.3) is
  normal and self-heals within the StartLimit. Only a *repeating* crash-loop is a
  real failure → revert the file you just deployed.

---

## 9. Post-deploy bookkeeping

- The `.deploy.bak.<TS>` files are the live rollback anchors — leave them in place
  until the deploy has soaked (a day of clean operation), then they can be pruned.
- Once a group has soaked clean, update [InsightFix.md](InsightFix.md) §1 "Fix
  status" and §6 from *staged* to *deployed (date)* so the docs stop saying
  "untouched."
- The two **deferred** items (bn.js 2.0.4→5.2.3, in-process bad-frame rate counter)
  are *not* in this runbook — they are test-gated changes tracked separately in
  [InsightFix.md](InsightFix.md) §5.
