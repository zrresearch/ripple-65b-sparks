#!/usr/bin/env bash
# Phase 3 on switch-dell: Ripple at TP=4, three configs as Phase 2; goldens vs the two-rank build, decode speed
cd ~/ripple-4x
export PATH=$HOME/.local/bin:$PATH
for cfg in "plain 0 1 1048576" "drafted 1 1 1048576" "streams4 1 4 262144"; do set -- $cfg
  echo "== $1: start $(date +%T)"
  HOST=127.0.0.1 DRAFTER=$2 STREAMS=$3 CONTEXT=$4 scripts/start.sh 2>&1 | grep -E "up after|warm-up|MemAvailable|engine|serving|die|rror|exited|busy"
  if ! curl -fsS -m 3 http://127.0.0.1:8888/v1/models >/dev/null; then echo "$1: NOT UP"; scripts/stop.sh >/dev/null 2>&1; continue; fi
  if [ $1 = streams4 ]; then python3 runs/golden.py http://127.0.0.1:8888 runs/phase3/tp4x4-$1.json --concurrent
  else python3 runs/golden.py http://127.0.0.1:8888 runs/phase3/tp4x4-$1.json
       python3 runs/decode_bench.py http://127.0.0.1:8888 Ripple-65B-Preview --runs 2 --out runs/phase3/bench-$1.json; fi
  python3 runs/golden.py --compare runs/phase2/tp4-$1.json runs/phase3/tp4x4-$1.json
  scripts/stop.sh 2>&1 | tail -1
done
echo "== done $(date +%T)"
