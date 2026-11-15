#!/bin/bash
# code decode at 16 streams (twice) per config "<bin>|<env>|<tag>", with the per-round log kept
D=$(dirname "$0"); J=$D/../sm.jar; API=http://127.0.0.1:4100/api/fleet; L=$(cat $D/dev-launcher-id)
st() { curl -s -b $J $API/launchers | python3 -c "import json,sys; print([l for l in json.load(sys.stdin) if l['id']=='$L'][0].get('state'))"; }
post() { curl -s -b $J -H 'content-type: application/json' -d '{}' $API/$1 >/dev/null; }
for cfg in "$@"; do
  IFS='|' read b e tag <<< "$cfg"
  ssh sw-head "echo $b > ~/ripple-dev/current-bin; echo '$e' > ~/ripple-dev/current-env"
  post launchers/$L/start; t0=$(date +%s)
  until [ "$(st)" = serving ]; do s=$(st); case "$s" in failed|error|idle) [ $(( $(date +%s)-t0 )) -gt 120 ] && { echo "START FAILED $tag $s"; exit 1; };; esac; sleep 10; done
  echo "[$tag] serving"
  id=$(curl -s -b $J -H 'content-type: application/json' -d '{"scope":"replica","nodeId":"sw-head","deploymentId":"'$L'","config":{"kind":"decode","concurrency":[16,16],"maxTokens":1024,"promptType":"code"}}' $API/benchmarks | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  python3 $D/../ripple-p4/benchwait.py $id > $D/res-code16-$tag.txt; echo "[$tag] code 16 ($id): $(python3 -c "
import json; r=json.loads(open('$D/res-code16-$tag.txt').read().split(chr(10),1)[1]); print(' / '.join('%d: %.1f'%(x['concurrency'],x['aggregateTokS']) for x in r['levels']))")"
  ssh sw-head "docker logs ripple-tf 2>&1 | grep -a lanes-price" > $D/rounds-$tag-code16.log
  post launchers/$L/stop; until [ "$(st)" = idle ]; do sleep 5; done
done
ssh sw-head "rm -f ~/ripple-dev/current-env"; echo "CODE16 DONE"
