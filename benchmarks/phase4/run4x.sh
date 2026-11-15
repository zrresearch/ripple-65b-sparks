#!/bin/bash
# Phase 4 final benchmarks, four Sparks, recipe build (patches 0001-0015)
D=$(cd "$(dirname "$0")" && pwd); S=$D/..; J=$S/sm.jar; API=http://127.0.0.1:4100/api/fleet; L=ln-mwfxi4er-e1b641
st() { curl -s -b $J $API/launchers | python3 -c "import json,sys; print([l for l in json.load(sys.stdin) if l['id']=='$L'][0].get('state'))"; }
post() { curl -s -b $J -H 'content-type: application/json' -d '{}' $API/$1 >/dev/null; }
bench() { id=$(curl -s -b $J -H 'content-type: application/json' -d '{"scope":"replica","nodeId":"sw-head","deploymentId":"'$L'","config":'"$1"'}' $API/benchmarks | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'); echo "$id" >> $D/bench-ids.txt; python3 $S/ripple-p4/benchwait.py $id > $D/$2; echo "[$(date +%T)] $2 ($id): $(head -1 $D/$2)"; }
echo "[$(date +%T)] part A: Phase 3's configs + 1M retrieval (recipe start.sh)"
ssh sw-head 'bash ~/ripple-4x/runs/p4.sh' 2>&1 | tee $D/p4-4x-partA.log
rsync -a sw-head:ripple-4x/runs/phase4/ $D/phase4-4x/
echo "[$(date +%T)] part B: 16 x 128K launcher, SparkMan decode / prose / prefill"
post launchers/$L/start; t0=$(date +%s)
until [ "$(st)" = serving ]; do s=$(st); case "$s" in failed|error|idle) [ $(( $(date +%s)-t0 )) -gt 120 ] && { echo "START FAILED $s"; exit 1; };; esac; sleep 10; done
echo "[$(date +%T)] serving"
bench '{"kind":"decode","concurrency":[1,2,4,8,16],"maxTokens":1024,"promptType":"code"}' res-decode-code.txt
python3 $S/ripple-p4/prose16.py http://<addr>:8888/v1 Ripple-65B-Preview-4x 1,2,4,8,16 | tee $D/res-prose.txt
bench '{"kind":"prefill","contextSizes":[4096,8192,16384,32768,65536,131072]}' res-prefill.txt
post launchers/$L/stop; until [ "$(st)" = idle ]; do sleep 5; done
echo "[$(date +%T)] P4 BENCH 4X DONE"
