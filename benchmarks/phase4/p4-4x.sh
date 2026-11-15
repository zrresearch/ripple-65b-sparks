#!/usr/bin/env bash
# Phase 4 on switch-dell: the recipe build with patches 0011-0015, Phase 3's three configs (goldens vs Phase 3, decode),
# then the 1M-token retrieval test at one stream
cd ~/ripple-4x
export PATH=$HOME/.local/bin:$PATH
for cfg in "plain 0 1 1048576" "drafted 1 1 1048576" "streams4 1 4 262144"; do set -- $cfg
  echo "== $1: start $(date +%T)"
  HOST=127.0.0.1 DRAFTER=$2 STREAMS=$3 CONTEXT=$4 scripts/start.sh 2>&1 | grep -E "up after|warm-up|MemAvailable|engine|serving|die|rror|exited|busy"
  if ! curl -fsS -m 3 http://127.0.0.1:8888/v1/models >/dev/null; then echo "$1: NOT UP"; scripts/stop.sh >/dev/null 2>&1; continue; fi
  if [ $1 = streams4 ]; then python3 runs/golden.py http://127.0.0.1:8888 runs/phase4/p4-$1.json --concurrent
  else python3 runs/golden.py http://127.0.0.1:8888 runs/phase4/p4-$1.json
       python3 runs/decode_bench.py http://127.0.0.1:8888 Ripple-65B-Preview --runs 2 --out runs/phase4/bench-$1.json; fi
  echo "-- vs Phase 3:"; python3 runs/golden.py --compare runs/phase3/tp4x4-$1.json runs/phase4/p4-$1.json
  scripts/stop.sh 2>&1 | tail -1
done
echo "== 1M retrieval: start $(date +%T)"
HOST=127.0.0.1 DRAFTER=1 STREAMS=1 CONTEXT=1048576 scripts/start.sh 2>&1 | grep -E "up after|engine|serving|die|rror|exited|busy"
python3 runs/longctx/ask.py runs/longctx/prompt-1m.json runs/phase4/result-1m.json
scripts/stop.sh 2>&1 | tail -1
echo "== P4 4x DONE $(date +%T)"
