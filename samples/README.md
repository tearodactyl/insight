samples/ — no-rebuild UI/UX experiments
=======================================

Staged copies of five raw-served `insight-ui-zero` templates, each carrying one
or more small UX experiments. Every change is **HTML-only**: it uses Bootstrap
classes and image assets **already present in the shipped bundle**, adds **no new
`angular-gettext` keys**, and therefore needs **no `grunt` rebuild and no
redeploy** — `public/views/*.html` are served raw via Angular's `$templateCache`/
`ng-include`.

These files live in this **repo-root `samples/` directory** (outside the
`insight-ui-zero` node-module repo), under `samples/views/...` — mirroring their
real paths under `insight-ui-zero/public/views/...`. They are **for review only**
here; promote a file by copying it over its live counterpart (see *Promote /
rollback* below).

Nothing under the docs repo's `error/` tree is touched — those mirror deployed
artifacts. Theme is **function-only semantic color** (green = ok, amber =
working, red = down); this is not a rebrand.

Scope names used are all confirmed present in `js/main.min.js` / the controllers:
`apiOnline`, `serverOnline`, `clienteOnline`, `sync.status`, `sync.error`,
`sync.startTs`, `sync.syncPercentage`, `info.connections`, `q`, `badQuery`,
`loading`, `currency.factor`, `currency.symbol`.

How image paths resolve
-----------------------

`public/index.html` sets `<base href="/" />`, so **every relative URL resolves
against the site root** (`https://<host>/…`). The UI is **not** served from the
site root, though: nginx `proxy_pass`es to bitcore (`http://127.0.0.1:3001/`),
which mounts the whole UI under **`/insight/`** (verified: origin
`/insight/css/custom.css` → 200, bare `/css/custom.css` → 404). A relative asset
URL therefore only resolves because the page itself is loaded under `/insight/`
and the browser requests it relative to that document. Reference an image by its
path **relative to the current page**, with **no leading slash** — a leading
slash escapes the `/insight/` mount and 404s:

```html
<img data-ng-src="img/logo.svg" alt="Zero">   <!-- correct: relative, stays under /insight/ -->
<img src="/img/logo.svg">                       <!-- WRONG: site root, escapes the /insight/ mount -> 404 -->
<img src="../img/logo.svg">                      <!-- WRONG: base href="/" makes ../ meaningless -->
```

Use `data-ng-src` (not `src`) when the element is inside an Angular scope, to
avoid a one-frame request for the literal un-interpolated URL. Assets referenced
here (`img/logo.svg`, `img/loading.gif`) already ship in `public/img/`.

> In `samples/views/` the `img/...` paths are illustrative (this subtree is not a
> served URL). They resolve correctly once a file is promoted into the live
> `public/views/` tree, because of `<base href="/">`.

The experiments
---------------

### 1 — `views/includes/connection.html` — positive heartbeat
The shipped template only renders the **failure** side (red `alert-danger`), so a
healthy node shows nothing. Adds a symmetric green `alert-success` "Live" box,
shown when `apiOnline && serverOnline && clienteOnline`.
**Verifies:** the websocket/`apiOnline` flag actually flips *true* (today only the
down state is ever visible).

### 2 — `views/includes/header.html` — brand image + traffic-light status
- **Image:** replaces the text brand `Zero` with `img/logo.svg` (`data-ng-src`).
- **Traffic-light:** `info.connections` rendered as a green/red Bootstrap `label`
  (green when peers > 0).
- **Status chip:** raw `sync.status` as a semantic `label` — green `finished`,
  amber `syncing`, red on `sync.error`.
**Verifies:** `getSync()` is polling and transitioning live from *any* page, not
just `/status`; peer connectivity at a glance.

### 3 — `views/status.html` — live Start Date + colored progress bar
- **Start Date:** was a hardcoded `Feb 19, 2017 10:26:40 AM UTC` literal with the
  real value hidden in the `title=` tooltip; now binds live `sync.startTs`.
- **Progress bar:** tinted by state (`progress-bar-success`/`-warning`/`-danger`)
  instead of the static `progress-bar-info`.
**Verifies:** the API actually delivers `startTs` (a stale literal was masking it).

### 4 — `views/includes/search.html` — query echo + spinner
- **Echo:** live `&rarr; {{q}}` under the box.
- **Image:** `img/loading.gif` spinner shown while `loading`.
**Verifies:** two-way binding fires before submit; `badQuery` toggles correctly
against known-good vs known-bad input.

### 5 — `views/includes/currency.html` — price-feed visibility
Adds a factor row to the currency dropdown: muted grey `factor: {{currency.factor}}`
when live, red `⚠ no price feed` when the factor is `0`/absent.
**Verifies operationally:** a `0` factor is the **visible signature of the Crash #4
expired-CA fallback** (`currency.js` sets `usd`/`btc` = 0 when the price fetch
fails) — observable without log-diving.

The CSS theme — `css/custom.css`
--------------------------------

A single **additive** override stylesheet, layered AFTER `css/main.min.css` via
one extra `<link>` in the sampled `index.html`. It re-tints **existing**
selectors only — touches no LESS source, needs no `grunt` rebuild, and rolls back
by removing the `<link>`. The base bundle is light, so this is a deliberately
**light** theme that works WITH the cascade rather than a dark inversion.

What it changes:

- **Page surface** — `body` background set to `#eef1f4`, a faint cool grey-blue
  ("icy/austere"), against the pure-white (`#ffffff`) panels. This needs
  `!important`: `main.min.css` has `body{background-color:#fff}` at the same
  specificity, so without it the override silently no-ops. The color was tuned by
  eye — the trap is `R=G` with blue maxed (`#cdd6f4`, `#dde9f1`, `#eeeeff`), which
  reads baby-blue or magenta/lavender; `#eef1f4` keeps `R<G<B` with blue **not**
  maxed, giving a cold grey-blue with no violet cast.
- **The two top green boxes unified** — the search input
  (`.navbar-form .form-control`, base `#7CAD23` bright yellow-green + white text =
  poor contrast) and the conn/status box (`.status`, `#597338` olive) were
  different shades. Both are forced to the darker olive `#597338` with white text
  so the search text is legible. `!important` is required because the base search
  rule is a two-selector rule that outranks a bare `#search`. Placeholder text is
  lightened (`#cfe3a6`) to read on the darker green.
- **Navbar left as designed** — an earlier attempt to force the bar
  white made white-on-white invisible links, so the navbar surface/link colors
  are NOT touched (white links on the black bar).
- **Selected nav item kept legible (white/black inversion)** — base
  `main.min.css` styles the selected (`.active`) item with a colored background +
  white text, but that wasn't reliably winning (so it rendered dark on the black
  bar), and its *hover* rule sets only a white background with **no text color**
  (white-on-white on hover). The override inverts the selected item to **white
  background + black text in all states (rest/hover/focus)** with `!important` —
  a clear "pressed" cue that can never go invisible. Unselected items are
  unaffected.
- **Links and accents** are a single deep-blue family (`#1a5e9c`, darker
  `#0f3f6e` on hover) — links, the active-currency dropdown highlight, the
  search focus ring, and the table row-hover all draw from this one color.
- **Hashes** are kept in the loaded Ubuntu font on the most-read elements for
  readability; panels/tables get faint blue-grey hairlines and a faint blue
  row-hover.

The "About" panel copy in `views/index.html` was also rewritten with clickable
links: **open-source** → the `insight-ui-zero` repo, **Zero Currency** → the
`Zero` repo, and **Github Issue tracker** → the issues page. The "About" heading
is kept.

> Cache note: `custom.css` and the `views/*.html` are static assets served by
> `express.static` (read from disk per request, no content caching), so a
> `systemctl restart bitcore.service` has **no** effect on their visibility. Only
> the Cloudflare edge cache (a 4h TTL CF injects — see `clng.md`) + the browser
> cache gate them. **Purge Cloudflare after every static deploy** or edits sit
> invisible behind the edge.

Bundle classes / assets relied on (all confirmed present)
---------------------------------------------------------

`alert-success`, `label`, `label-success`, `label-danger`, `label-warning`,
`progress-bar-success`, `progress-bar-warning`, `progress-bar-danger`,
`glyphicon-ok`, `glyphicon-warning-sign`, `text-muted`, `text-danger`, the
`divider` dropdown class — plus `img/logo.svg` and `img/loading.gif`.

Note on diffs
-------------

The staged copies also normalized a handful of pre-existing **trailing-whitespace**
lines (cosmetic, unrelated to the experiments). When reviewing a `diff -u` against
the live original, those whitespace-only hunks are noise; the substantive changes
are the commented `SAMPLE` blocks.

Promote / rollback
------------------

Preview one file's substantive diff (run from the repo root):

```sh
diff -u insight-ui-zero/public/views/includes/header.html \
        samples/views/includes/header.html
```

Promote a sample into the live raw-served tree (back up first). Back up with a
**timestamped** suffix `.YYYYMMDD-HHMMSS` (host-local clock), NOT a bare `.bak` —
unique suffixes never collide, sort chronologically, and record when each backup
was taken:

```sh
LIVE=insight-ui-zero/public/views
ts=$(date +%Y%m%d-%H%M%S)                                          # one ts per batch
cp -p "$LIVE/includes/header.html" "$LIVE/includes/header.html.$ts"  # rollback copy
cp samples/views/includes/header.html "$LIVE/includes/header.html"
```

No build step. The change is live on the next page load — but for **static assets
served behind Cloudflare** (`custom.css`, `views/*.html`), hard-refresh AND purge
the Cloudflare edge cache (4h injected TTL — see `clng.md`); a bitcore restart
does nothing for them. Roll back by copying the timestamped backup back over the
original. Nothing reaches the host until you copy it there explicitly.
