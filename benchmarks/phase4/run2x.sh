#!/bin/bash
# Phase 4 final benchmarks, two Sparks, recipe build (patches 0001-0015)
D=$(cd "$(dirname "$0")" && pwd); S=$D/..; J=$S/sm.jar; API=http://127.0.0.1:4100/api/fleet; LP=ln-mwccslpu-e84983; L4=ln-mwh1954d-8991ba
st() { curl -s -b $J $API/launchers | python3 -c "import json,sys; print([l for l in json.load(sys.stdin) if l['id']=='$1'][0].get('state'))"; }
post() { curl -s -b $J -H 'content-type: application/json' -d '{}' $API/$1 >/dev/null; }
up() { post launchers/$1/start; t0=$(date +%s); until [ "$(st $1)" = serving ]; do s=$(st $1); case "$s" in failed|error|idle) [ $(( $(date +%s)-t0 )) -gt 120 ] && { echo "START FAILED $1 $s"; exit 1; };; esac; sleep 10; done; echo "[$(date +%T)] $1 serving"; }
down() { post launchers/$1/stop; until [ "$(st $1)" = idle ]; do sleep 5; done; }
bench() { id=$(curl -s -b $J -H 'content-type: application/json' -d '{"scope":"replica","nodeId":"pny-head","deploymentId":"'$1'","config":'"$2"'}' $API/benchmarks | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'); echo "$id" >> $D/bench-ids-2x.txt; python3 $S/ripple-p4/benchwait.py $id > $D/$3; echo "[$(date +%T)] $3 ($id): $(head -1 $D/$3)"; }
echo "[$(date +%T)] part A: Phase 2's configs + 1M retrieval (recipe start.sh)"
ssh pny-head 'bash ~/ripple-2x/runs/p4.sh' 2>&1 | tee $D/p4-2x-partA.log
rsync -a pny-head:ripple-2x/runs/phase4/ $D/phase4-2x/
echo "[$(date +%T)] part B1: production 2x launcher (1 x 1M): SparkMan prefill"
up $LP; bench $LP '{"kind":"prefill","contextSizes":[4096,8192,16384,32768,65536,131072]}' res-prefill-2x.txt; down $LP
echo "[$(date +%T)] part B2: 4 x 256K launcher: SparkMan code decode 1/2/4, prose 1/2/4"
up $L4; bench $L4 '{"kind":"decode","concurrency":[1,2,4],"maxTokens":1024,"promptType":"code"}' res-decode-code-2x.txt
python3 $S/ripple-p4/prose16.py http://<addr>:8888/v1 Ripple-65B-Preview 1,2,4 | tee $D/res-prose-2x.txt; down $L4
echo "[$(date +%T)] P4 BENCH 2X DONE"
