samples/ — deployed UI mirror (production)
==========================================

Byte-for-byte copies of the **production** `insight-ui-zero/public/` tree
(`<bitcore-node>/node_modules/insight-ui-zero/public/`), including the full
`img/icons/` directory referenced by `index.html` and `main.min.css`.
The nested `insight-ui-zero/` package repo in this docs checkout is kept in sync
with `samples/` for the same paths.

Every file here is **HTML/CSS/assets only**: Bootstrap classes and images already in
the shipped bundle, no new `angular-gettext` keys, **no `grunt` rebuild** --
`public/views/*.html` are served raw via Angular `$templateCache` / `ng-include`.

Backend companion: `error/currency.js` mirrors production
`insight-api-zero/lib/currency.js` (same content as
`insight-api-zero/lib/currency.js` in the nested package repo).

File inventory
--------------

Paths mirror `insight-ui-zero/public/...`:

| Path under `samples/` | Role |
|---|---|
| `index.html` | Mainnet title/meta, PNG favicon links, `custom.css` link |
| `css/custom.css` | Ice-blue light theme override |
| `views/index.html` | About panel with repo links |
| `views/status.html` | Mainnet label, Warnings filter, hardcoded genesis dates, blue progress bar |
| `views/includes/connection.html` | Red failure banner only; zerod wording (§4a) |
| `views/includes/header.html` | Text brand **Zero**; plain Conn count; sync tooltip |
| `views/includes/search.html` | Upstream search form (no extra spinner or query echo) |
| `views/includes/currency.html` | Price-feed visibility row (`factor:` / `no price feed`) |
| `img/icons/favicon.ico` | Legacy tab icon; `index.html` `shortcut icon` link (upstream; kept alongside PNGs) |
| `img/icons/favicon-16x16.png` | Sized PNG favicon (Fixes round; modern browsers) |
| `img/icons/favicon-32x32.png` | Sized PNG favicon (Fixes round; modern browsers) |
| `img/icons/copy.png` | Upstream UI sprite for `.btn-copy` in `main.min.css` (not a favicon; same folder on the server) |

Deployed changes (production and this tree)
-------------------------------------------

### Round 2 (mainnet polish)

- **`index.html`**: static `<title>` and meta say **Zero Insight** (mainnet), not testnet default.
- **`views/status.html`**: **Network** shows `mainnet` when API returns `livenet`.
- **`views/status.html`**: **Warnings** row binds `info.errors` but hides partition-check
  noise (`blocks received in the last`). Other warnings still show when present.

### Theme and favicons

- **`css/custom.css`**: additive override after `main.min.css` (page grey-blue, white
  panels, navbar hover-invert, unified green status/search boxes, link colours,
  currency dropdown active state). See *CSS theme* below.
- **`index.html`**: extra `<link>` for `custom.css`; PNG favicon links added beside the
  existing `.ico` `shortcut icon` link.
- **`img/icons/`**: mirror includes upstream `favicon.ico` and `copy.png` (copy-button
  sprite) plus the two PNG favicons added in the Fixes round -- promote the whole
  directory, not the PNGs alone.
- **`views/index.html`**: About copy with links to `insight-ui-zero`, `Zero`, issues.

### Status page dates and sync display

- **Start Date** and **Genesis Mined**: hardcoded Zero genesis timestamps (ProphetAlgorithms,
  2021). Do **not** bind `{{sync.startTs}}` -- `/sync` does not return it (indexes
  live in zerod; see `error/insight-api-zero/README.md`).
- **Finish Date** row: removed (`sync.endTs` never returned).
- **Sync progress bar**: stock `progress-bar-info` (blue), not state-coloured bars.
- **Navbar sync tooltip**: `syncPercentage` and `blockChainHeight` only (no
  `syncedBlocks` / `skippedBlocks`).

### Connection banner (§4a)

- **`connection.html`**: `!apiOnline` text reads "Can't connect to zerod to get live
  updates"; `translate` removed on that `<p>`. **No** green "Live" success banner.

### Header and search

- **`header.html`**: text brand **Zero** (not `logo.svg`). Plain connection count
  (no traffic-light labels or sync-status chip).
- **`search.html`**: upstream only. Upstream CSS still shows `loading.gif` **inside**
  the input while a search runs; there is no duplicate GIF beside the box.

### Currency dropdown and API

- **`currency.html`**: footer row shows `factor: {{currency.factor}}` when the feed
  works, or red `no price feed` when absent. Native ZER shows `factor: 1`.
- **`insight-api-zero/lib/currency.js`**: crash #4 CA fix plus CoinGecko **User-Agent**
  header and **`binance: self.usd`** in the JSON (UI `main.min.js` still reads
  `res.data.binance`).

Not deployed (rejected experiments -- do not promote)
-----------------------------------------------------

These appeared in a short-lived Fixes commit (2026-06-27) and were **reverted in production**:

- Green **Live** `alert-success` box in `connection.html`
- **`logo.svg`** navbar brand (2014 BitPay wordmark; unusable at navbar height)
- Traffic-light **label** chips on Conn count and `sync.status`
- State-coloured sync **progress bar** (green/amber/red)
- **`{{sync.startTs}}`** Start Date binding (empty cell -- API has no field)
- **Finish Date** row (`sync.endTs`)
- **`syncedBlocks` / `skippedBlocks`** navbar tooltip
- Search **query echo** (`&rarr; {{q}}` under the box)
- Extra **`loading.gif` `<img>`** beside the search input

`/sync` API fields
------------------

Today's `/insight-api-zero/sync` JSON:

`status`, `blockChainHeight`, `syncPercentage`, `height`, `error`, `type`

Legacy Insight fields **`startTs`**, **`endTs`**, **`syncedBlocks`** are not returned
on Zero (Safecoin/Pirate forks match this shape). Do not bind them in templates.

How image paths resolve
-----------------------

`index.html` sets `<base href="/" />`. nginx proxies to bitcore on port 3001; the UI
mount is **`/insight/`**. Use paths **relative to the page**, no leading slash:

```html
<link rel="icon" href="img/icons/favicon-32x32.png">   <!-- correct under /insight/ -->
<link rel="icon" href="/img/icons/favicon-32x32.png">  <!-- WRONG: escapes mount -> 404 -->
```

Use `data-ng-src` (not `src`) for Angular-bound images.

The CSS theme -- `css/custom.css`
---------------------------------

Single additive stylesheet layered **after** `css/main.min.css`. No LESS, no grunt.
Rollback: remove the `<link>` from `index.html`.

What it overrides (each rule needed because base differs):

- **Page surface** -- `body` `#eef1f4` (`!important` vs base `#fff`).
- **Panels** -- `.well` / `.col-gray` forced white; hairlines `#dbe4ec`.
- **Navbar** -- white-on-black at rest, inverts on hover; no `.active` styling
  (bundled `ui-route` never applies `.active`).
- **Search + status boxes** -- both `#597338` (base search box was brighter green).
- **Links** -- `#1a5e9c` / hover `#0f3f6e`.
- **Currency dropdown** -- `a.active` highlight (base targets `li.active`).

Scope names (confirmed in `js/main.min.js`)
-------------------------------------------

`apiOnline`, `serverOnline`, `clienteOnline`, `sync.status`, `sync.error`,
`sync.syncPercentage`, `sync.blockChainHeight`, `info.connections`, `info.errors`,
`currency.factor`, `q`, `badQuery`, `loading`.

Verification checksums (production deploy, 2026-06-29)
----------------------------------------------

```text
connection.html   ae74ae7aee362fc85a0535106eb3705b
currency.js       49ae99a2e1fa196acde9bc83e7bae81f
```

Promote / rollback
------------------

Preview diff (from docs repo root):

```sh
diff -u insight-ui-zero/public/views/status.html samples/views/status.html
```

Promote one UI file to the production host (back up with timestamp suffix first).
Host-specific deploy steps (ssh alias, cache purge): maintainers' internal runbook only
— not linked from distributable docs. Generic package-update path:
[InsightBlock.md §5.7](../InsightBlock.md#57-deploying-updated-explorer-packages).
Static cache flush: [InsightFix.md](../InsightFix.md#flushing-caches-after-a-static-deploy).

```sh
LIVE=<bitcore-node>/node_modules/insight-ui-zero/public
ts=$(date +%Y%m%d-%H%M%S)
cp -p "$LIVE/views/status.html" "$LIVE/views/status.html.$ts"
cp samples/views/status.html "$LIVE/views/status.html"
```

API `currency.js` needs a **bitcore restart** after copy. Static HTML/CSS needs **no**
restart; purge Cloudflare if the edge serves stale bytes. See
[InsightFix.md](../InsightFix.md#flushing-caches-after-a-static-deploy).
