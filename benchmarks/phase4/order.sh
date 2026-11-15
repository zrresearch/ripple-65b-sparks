#!/bin/bash
# the benchmark's order on a fresh server: SparkMan code 1-16, then prose 1, 2, 4, 4, 4 (round logs kept); per config
D=$(dirname "$0"); J=$D/../sm.jar; API=http://127.0.0.1:4100/api/fleet; L=$(cat $D/dev-launcher-id)
until grep -q "PROBE DONE\|START FAILED" /var/lib/sparkman/jobs/job-mwgzi24l-4003f6/output.log && ! pgrep -f "bash $D/probe.sh" >/dev/null; do sleep 30; done
st() { curl -s -b $J $API/launchers | python3 -c "import json,sys; print([l for l in json.load(sys.stdin) if l['id']=='$L'][0].get('state'))"; }
post() { curl -s -b $J -H 'content-type: application/json' -d '{}' $API/$1 >/dev/null; }
for cfg in "$@"; do
  IFS='|' read b e tag <<< "$cfg"
  ssh sw-head "echo $b > ~/ripple-dev/current-bin; echo '$e' > ~/ripple-dev/current-env"
  post launchers/$L/start; t0=$(date +%s)
  until [ "$(st)" = serving ]; do s=$(st); case "$s" in failed|error|idle) [ $(( $(date +%s)-t0 )) -gt 120 ] && { echo "START FAILED $tag $s"; exit 1; };; esac; sleep 10; done
  echo "[$(date +%T)] [$tag] serving"
  id=$(curl -s -b $J -H 'content-type: application/json' -d '{"scope":"replica","nodeId":"sw-head","deploymentId":"'$L'","config":{"kind":"decode","concurrency":[1,2,4,8,16],"maxTokens":1024,"promptType":"code"}}' $API/benchmarks | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  python3 $D/../ripple-p4/benchwait.py $id > $D/order-code-$tag.txt; echo "[$tag] code ($id): $(python3 -c "
import json; r=json.loads(open('$D/order-code-$tag.txt').read().split(chr(10),1)[1]); print(' / '.join('%d: %.1f'%(x['concurrency'],x['aggregateTokS']) for x in r['levels']))")"
  n0=$(ssh sw-head "docker logs ripple-tf 2>&1 | grep -ac 'lanes-'")
  python3 $D/../ripple-p4/prose16.py http://<addr>:8888/v1 Ripple-65B-Preview-4x 1,2,4,4,4 | sed "s/^/[$tag prose] /"
  ssh sw-head "docker logs ripple-tf 2>&1 | grep -a 'lanes-' | tail -n +$((n0+1))" > $D/order-$tag-prose.log
  post launchers/$L/stop; until [ "$(st)" = idle ]; do sleep 5; done
done
ssh sw-head "rm -f ~/ripple-dev/current-env"; echo "ORDER DONE"
