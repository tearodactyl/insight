# samples/ — UI reference files

Reference copies of selected `insight-ui-zero/public/` files (HTML, CSS, images)
maintained in the docs repository. See the [documentation map](../README.md#documentation-map).

Every file here is **HTML, CSS, or static assets only** — no `grunt` rebuild. Templates
are served raw via Angular `$templateCache` / `ng-include`.

Backend companion for the price feed: [`error/currency.js`](../error/currency.js).

## File inventory

Paths mirror `insight-ui-zero/public/...`:

| Path under `samples/` | Role |
|---|---|
| `index.html` | Mainnet title/meta, PNG favicon links, `custom.css` link |
| `css/custom.css` | Light theme override layered after `main.min.css` |
| `views/index.html` | About panel with repo links |
| `views/status.html` | Mainnet label, Warnings filter, hardcoded genesis dates |
| `views/includes/connection.html` | Offline banner; zerod wording |
| `views/includes/header.html` | Text brand **Zero**; connection count |
| `views/includes/search.html` | Search form |
| `views/includes/currency.html` | Currency dropdown; footer visibility row |
| `img/icons/favicon.ico` | Legacy tab icon |
| `img/icons/favicon-16x16.png` | Sized PNG favicon |
| `img/icons/favicon-32x32.png` | Sized PNG favicon |
| `img/icons/copy.png` | Copy-button sprite (`.btn-copy` in `main.min.css`) |

## `/sync` API fields

Today's `/insight-api-zero/sync` JSON:

`status`, `blockChainHeight`, `syncPercentage`, `height`, `error`, `type`

Do not bind legacy fields `startTs`, `endTs`, or `syncedBlocks` in templates — they
are not returned on Zero.

## Image and asset paths

`index.html` sets `<base href="/" />`. The UI mount is **`/insight/`**. Use paths
relative to the page (no leading slash on assets under the mount). Use `data-ng-src`
(not `src`) for Angular-bound images.

## CSS theme — `css/custom.css`

Single additive stylesheet after `css/main.min.css`. Overrides page surface, panels,
navbar, search/status boxes, links, and currency dropdown active state. Rollback by
removing the `<link>` from `index.html`.

## Scope names (in `js/main.min.js`)

`apiOnline`, `serverOnline`, `clienteOnline`, `sync.status`, `sync.error`,
`sync.syncPercentage`, `sync.blockChainHeight`, `info.connections`, `info.errors`,
`currency.factor`, `q`, `badQuery`, `loading`.

Behaviour bound to those names (including currency conversion) is implemented in the
compiled UI bundle (`public/js/main.min.js`), not in this directory. Which paths need
grunt, hand-patching, or neither: [InsightPort.md §6.3](../InsightPort.md#63-did-horizens-changes-require-a-gruntbower-rebuild-yes--verified)
(load order, decision table, hand-patch workflow, §6.4 rebuild prerequisites).

Backend `.js` under `insight-api-zero/lib/` is separate from the UI bundle; see
[`error/`](../error/) and InsightFix.md.
