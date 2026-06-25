# Node version — replicating the pinned runtime

The Zero Insight explorer (`bitcore`) runs on **Node v8.17.0**. This is the admin
runbook for *reproducing* that pinned environment on a host. The version is not
incidental: the native modules and dependency pins (e.g. `bn.js`) are built against
this runtime, and the daemon's TLS behavior depends on the OpenSSL it bundles. Do
not substitute a different Node without going through the upgrade evaluation.

> This runbook covers only how to *reproduce* the pinned runtime. The constraints
> behind the pin — why Node 8 is held, OpenSSL/native-module considerations, and any
> future upgrade evaluation — are out of scope here.

## 1. The runtime that matters: the service is PATH-independent

`bitcore.service` pins the node binary by **full path** in `ExecStart`, so the
service always runs v8.17.0 regardless of what a shell's bare `node` resolves to:

    <NVM_DIR>/versions/node/v8.17.0/bin/node ./node_modules/bitcore-node-zero/bin/bitcore-node start

This is the single most important fact: the *service* is unaffected by PATH or by
nvm's interactive setup. Everything below is about making the **interactive / CLI**
side match the service, so that `node --check` and ad-hoc tooling run under the same
runtime the service uses.

## 2. Install nvm + Node v8.17.0

    # install nvm (see nvm's repo for the current bootstrap line), then:
    nvm install 8.17.0
    nvm alias default 8.17.0

This yields `<NVM_DIR>/versions/node/v8.17.0/bin/{node,npm}`; `npm` pairs as 6.13.4.

## 3. Make every shell form resolve to the pinned node

nvm is normally sourced from `~/.bashrc`, which often returns early for
non-interactive shells (a guard like `[ -z "$PS1" ] && return` near the top). If nvm
is sourced *below* that guard, non-interactive shells (`ssh host 'cmd'`, scripts)
never activate nvm and `node` falls through to whatever else is on PATH — a
different, wrong version. Load nvm **above** the interactive guard so all shell
forms activate it:

    # in ~/.bashrc, ABOVE the interactive guard:
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" --no-use
    nvm use default >/dev/null 2>&1

    # in ~/.profile, for login shells (belt-and-suspenders):
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

Any apt-installed `/usr/bin/node` can be left in place — other system tooling may
use it; nvm's bin simply precedes it on PATH.

## 4. Verify all three shell forms

All of these must resolve `node` to the v8.17.0 binary:

    node --version              # v8.17.0  (non-interactive)
    bash -lc "node --version"   # v8.17.0  (login)
    bash -ic "node --version"   # v8.17.0  (interactive)

`npm --version` should report 6.13.4.

## 5. Rule of thumb — match the service runtime explicitly

For anything that must match the live runtime (e.g. `node --check` of a staged fix
before deploy), prefer the **explicit service path** over a bare `node`, so a
mis-resolving shell can never check under the wrong version:

    NODE=<NVM_DIR>/versions/node/v8.17.0/bin/node
    $NODE --check <file>
