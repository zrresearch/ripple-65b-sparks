#!/bin/bash
# A/B on 4 Sparks, one new build: scatter on (goldens + prefill), then TF_RICURSIVE_SCATTER=0 (prefill)
D=$(dirname "$0")
start() { ssh sw-head 'cd ~/ripple-4x && scripts/stop.sh >/dev/null 2>&1; BIN=$HOME/ripple-dev/zig-out STREAMS=1 CONTEXT=1048576 SERVED_NAME=Ripple-65B-Preview EXTRA_ENV="'"$1"'" timeout 900 scripts/start.sh > /tmp/rp-start.log 2>&1; tail -1 /tmp/rp-start.log'; }
start ""
python3 $D/golden.py http://<addr>:8888 $D/new-drafted.json && python3 $D/golden.py --compare $D/tp4x4-drafted.json $D/new-drafted.json; echo "golden exit $?"
echo "[scatter on] $(python3 $D/pf8k.py 7600)"; echo "[scatter on] $(python3 $D/pf8k.py 30000)"
start "-e TF_RICURSIVE_SCATTER=0"
echo "[scatter off] $(python3 $D/pf8k.py 7600)"; echo "[scatter off] $(python3 $D/pf8k.py 30000)"
ssh sw-head 'cd ~/ripple-4x && scripts/stop.sh 2>&1 | tail -1'
echo "AB DONE"
