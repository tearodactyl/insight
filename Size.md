# Insight Explorer — UTXO / Transaction / Response-Size Findings

Working notes on response-size limits in the Zero (ZER) Insight explorer: what the
real worst-case addresses look like, how the crash-#3 caps behave against them, and
ideas for the durable fix. Captured during the staged-fix deploy.

- Host: HOST (`ssh HOST`)
- Stack: one Node v8.17.0 `bitcore` process, ~1.4 GB JS heap, fronting `zerod`.
- Chain tip at time of measurement: block **2,479,518**.
- File under test: `insight-api-zero/lib/addresses.js` (crash-#3 hardened, deployed).

---

## 1. The crash-#3 door (recap)

One Express `response.send()` built a ~163 MB string on the ~1.4 GB Node-8 heap and
aborted the process (JS-heap OOM). The unbounded doors are the unpaginated address
responses:

- the address **summary** s full `txids` list, and
- the **`/utxo`** and **`/addrs/.../utxo`** arrays for a hot address.

The hardening (`addresses.js`) bounds these:

| Constant | Value (deployed) | Role |
|---|---|---|
| `MAX_RESPONSE_BYTES` | 50 MB | **Hard OOM backstop.** Serialize, measure, `413` if body > 50 MB. Catches ANY response by serialized size regardless of element count. |
| `MAX_TXIDS` | 100,000 | Truncate the summary txid list; set `txAppearancesTruncated` + `txAppearancesLimit`. |
| `MAX_UTXOS` | 100,000 | `413` if a utxo array exceeds this count. |

`MAX_RESPONSE_BYTES` is the real guard. The count caps are a cheap early-out so we
do not even build arrays we know are too big.

---

## 2. Measured worst-case addresses

The busiest addresses on the chain are below. They received a slice of nearly every block subsidy,
 so their tx and UTXO counts are enormous.

| # in list | Address | txApperances | Balance (ZER) | UTXO count | `/utxo` result | Notes |
|---|---|---:|---:|---:|---|---|
| 1 | `t3hmg6WApjqVFw9oPWTDy4JLEqXcUWthg5v` | 388,931 | 0 | 0 | **200** (2 B) | fully drained |
| 2 | `t3hrh5M7eaGA5zXCitPXz2pbe146GkVPWHs` | 800,641 | 207,596.925 | **512,585** | **413** | over 100k cap |
| 3 | `t3aWmHqBGS7watoKQLa7uykeTaYHoYqM361` | 800,005 | 162,000.001 | **800,003** | **413** | over 100k cap |

Summary (`/addr/...?noTxList=1`) returned **200** for all four (small bodies).

### Latency observation
`/utxo` fetches the **entire** UTXO set from the node before the count cap can
reject it, so the 413 path is slow on the mega-addresses:
- #2 (512k): ~10.7 s to 413
- #3 (800k): ~17.8 s to 413
- #4 (79.5k): 1.73 s to a full 200

The cap prevents the OOM but does **not** prevent the upstream fetch cost.

---

## 3. Size estimates (serialized JSON, API-shaped)

Per-UTXO API object (`transformUtxo`) is roughly **260-280 bytes** serialized
(address, txid, vout, scriptPubKey hex, amount, satoshis, height, confirmations).

| UTXO count | Approx `/utxo` body | vs 50 MB ceiling | vs ~1.4 GB heap |
|---:|---:|---|---|
| 79,513 (#4) | ~20.7 MB (measured) | under | safe |
| ~100,000 (cap) | ~26-38 MB | under | safe |
| 512,585 (#2) | ~135 MB | **over** | OOM risk if served whole |
| 800,003 (#3) | ~210 MB | **over** | **would OOM** the process |

This confirms #3 served whole (~210 MB on a 1.4 GB heap) is exactly the crash-#3
abort. The cap is correctly refusing it.

---

## 4. Validation outcome

- Service survived ALL of the above: `NRestarts=0`, `active`, no `heap` / `OOM` /
  `RangeError` in the journal.
- The 413 caps fired exactly where the math says they must (#2, #3).
- The #4 whale now serves its full ~20.7 MB UTXO set after the cap bump
  (was 413 pre-bump). End-to-end serialization at that size is fine.

**Crash #3 hardening is proven against the real worst case** (an 800k-UTXO,
~210 MB would-be response).

---

## 5. Cap-sizing decision

`MAX_UTXOS = 100000` was calibrated against #4 (~79.5k), under the mistaken
assumption it was the busiest address. The true worst cases (#2, #3) are 5-8x larger
and still 413 — **and that is correct**: an 800k-UTXO / ~210 MB response must never
be built whole on this heap.

**Decision: keep caps at 100k.** Do NOT raise them to serve #2/#3 in full; that
re-introduces the OOM we just closed. The bump was still worthwhile (it serves the
common-large #4 class fully).

---

## 6. Ideas / open follow-ups

1. **Pagination on `/utxo`** (the real fix). Add `from`/`to` (or `pageNum`) to the
   utxo endpoints so the 413 message ("narrow the query") becomes actionable.
   - Requires node-side support to fetch a UTXO *slice* rather than all-then-slice,
     otherwise the upstream-fetch latency (17.8 s for #3) and memory cost remain.
   - Mirror the existing `from`/`to` pattern already used by `multitxs`.

2. **Reduce the upstream-fetch cost.** Today the cap rejects only AFTER the node
   returns the full UTXO set. A pre-count (e.g. `getAddressTxids`/balance-style
   count RPC) could let us 413 BEFORE pulling 800k objects across RPC, cutting the
   ~10-18 s latency to near-zero on the reject path.

3. **Stream instead of buffer.** For large-but-under-cap responses, stream the JSON
   array (chunked) rather than `JSON.stringify` the whole thing, lowering peak heap.
   Would let the byte ceiling rise safely. More invasive.

4. **Summary txid pagination.** `MAX_TXIDS` currently truncates silently-ish
   (flagged via `txAppearancesTruncated`). Founders addresses have 388k-800k
   appearances; the from/to summary paging already exists - document/encourage it
   for these addresses.

5. **Per-endpoint ceilings.** Consider a lower byte ceiling for `/utxo` specifically
   vs other endpoints, since utxo bodies dominate the OOM risk.

