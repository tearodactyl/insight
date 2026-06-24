# Node version on HOST

Context: the Zero Insight explorer (`bitcore`) runs on Node v8.17.0; see `~/zero/insight/InsightBlock.md` / `InsightPort.md`.

## The runtime that matters

`bitcore.service` pins the node binary by full path in `ExecStart`:

    /home/ubuntu/.nvm/versions/node/v8.17.0/bin/node ./node_modules/bitcore-node-zero/bin/bitcore-node start

So the **service is unaffected by PATH** — it always runs v8.17.0 regardless of what
a shell's bare `node` resolves to. This note is only about the interactive/CLI side.

## The discrepancy that existed (before 2026-06-23)

- `nvm` default alias: `v8.17.0` (the only nvm-installed version).
- apt-installed system node: **`/usr/bin/node` = v8.10.0** (package `nodejs`, Oct 2018).
- `~/.bashrc` sourced nvm — but **below** its interactive guard on line 2:

      [ -z "$PS1" ] && return

  Non-interactive `ssh HOST 'cmd'` and `bash -l` shells return before reaching the
  nvm lines, so nvm never activated and bare `node` fell through to `/usr/bin/node`
  (v8.10.0). Result: interactive shells got v8.17.0; everything else got v8.10.0.

This was a footgun for `node --check` during a fix deploy: running it via a plain
`ssh HOST 'node --check ...'` checked under v8.10.0, not the service's v8.17.0.

## The fix applied

1. `~/.bashrc` — nvm early-load block inserted **above** the interactive guard:

       export NVM_DIR="$HOME/.nvm"
       [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" --no-use
       nvm use default >/dev/null 2>&1

   So non-interactive ssh and login shells also activate nvm default.

2. `~/.profile` — appended a standard nvm load for login shells (belt-and-suspenders):

       export NVM_DIR="$HOME/.nvm"
       [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

3. `/usr/bin/node` (v8.10.0, apt `nodejs`) **left in place** — other system tooling
   may use it; nvm's bin now simply precedes it on PATH.

Backups taken at change time:

    ~/.bashrc.bak.20260623-014955
    ~/.profile.bak.20260623-014955

## Verified after

All three shell forms resolve `node` → `/home/ubuntu/.nvm/versions/node/v8.17.0/bin/node`:

    ssh HOST 'node --version'              # v8.17.0  (non-interactive)
    ssh HOST 'bash -lc "node --version"'   # v8.17.0  (login)
    ssh HOST 'bash -ic "node --version"'   # v8.17.0  (interactive)

`npm` resolves to the matching `v8.17.0/bin/npm` (6.13.4).

## Rollback (these dotfile edits only)

    cp ~/.bashrc.bak.20260623-014955 ~/.bashrc
    cp ~/.profile.bak.20260623-014955 ~/.profile

## Rule of thumb

For anything that must match the live runtime (e.g. `node --check` of a staged fix
before deploy), prefer the **explicit service path** and don't rely on bare `node`:

    NODE=/home/ubuntu/.nvm/versions/node/v8.17.0/bin/node
    $NODE --check <file>
