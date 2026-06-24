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
against the site root**, which nginx maps to this `public/` tree. Reference an
image by its path relative to `public/`, with **no leading slash**:

```html
<img data-ng-src="img/logo.svg" alt="Zero">   <!-- correct -->
<img src="/img/logo.svg">                       <!-- WRONG: server root, 404 behind nginx -->
<img src="../img/logo.svg">                      <!-- WRONG: base makes ../ meaningless -->
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

Promote a sample into the live raw-served tree (back up first):

```sh
LIVE=insight-ui-zero/public/views
cp "$LIVE/includes/header.html" "$LIVE/includes/header.html.bak"   # rollback copy
cp samples/views/includes/header.html "$LIVE/includes/header.html"
```

No build step. The change is live on the next page load (hard-refresh to defeat
the browser template cache). Roll back by restoring the `.bak`. Nothing reaches
the host until you copy it there explicitly.
