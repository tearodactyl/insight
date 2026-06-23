#!/bin/sh
# /home/ubuntu/zero/mynode/bitcore_start.sh
# Hand-launch / legacy path only. The live stack runs under systemd
# (zerod.service + bitcore.service); this script is the manual fallback used
# for diagnostics and the spawn-mode rollback. Run from ~/zero/mynode.
# Output goes to start.out; the prior run's log is moved aside first so the
# redirect below does not clobber the only record of the last hand-launch.
[ -s start.out ] && mv start.out "start_$(date +%Y%m%d-%H%M%S).out"
./node_modules/bitcore-node-zero/bin/bitcore-node start > start.out 2>&1 &
