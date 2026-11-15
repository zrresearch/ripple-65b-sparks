#!/bin/bash
# decode A/B through a dev-build launcher: SparkMan code decode 1..16 streams + prose 1..16, per build named in $@
D=$(dirname "$0"); J=$D/../sm.jar; API=http://127.0.0.1:4100/api/fleet; L=$(cat $D/dev-launcher-id)
st() { curl -s -b $J $API/launchers | python3 -c "import json,sys; print([l for l in json.load(sys.stdin) if l['id']=='$L'][0].get('state'))"; }
post() { curl -s -b $J -H 'content-type: application/json' -d '{}' $API/$1 >/dev/null; }
for b in "$@"; do
  ssh sw-head "echo $b > ~/ripple-dev/current-bin"
  post launchers/$L/start; t0=$(date +%s)
  until [ "$(st)" = serving ]; do s=$(st); case "$s" in failed|error|idle) [ $(( $(date +%s)-t0 )) -gt 120 ] && { echo "START FAILED $b $s"; exit 1; };; esac; sleep 10; done
  echo "[$b] serving; $(ssh sw-head 'docker logs ripple-tf 2>&1 | grep -a "target windows" | tail -1')"
  id=$(curl -s -b $J -H 'content-type: application/json' -d '{"scope":"replica","nodeId":"sw-head","deploymentId":"'$L'","config":{"kind":"decode","concurrency":[1,2,4,8,16],"maxTokens":1024,"promptType":"code"}}' $API/benchmarks | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  python3 $D/../ripple-p4/benchwait.py $id > $D/res-decode-$b.txt; echo "[$b] code decode ($id): $(python3 -c "
import json; r=json.loads(open('$D/res-decode-$b.txt').read().split(chr(10),1)[1]); print(' / '.join('%d: %.1f'%(x['concurrency'],x['aggregateTokS']) for x in r['levels']))")"
  echo "[$b] prose:"; python3 $D/../ripple-p4/prose16.py http://<addr>:8888/v1 Ripple-65B-Preview-4x 1,2,4,8,16 | tee $D/res-prose-$b.txt
  post launchers/$L/stop; t0=$(date +%s); until [ "$(st)" = idle ]; do sleep 5; done
done
echo "DEC DONE"
