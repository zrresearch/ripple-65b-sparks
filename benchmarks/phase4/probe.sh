#!/bin/bash
# 4-stream prose drop: per config "<bin>|<env>|<tag>": prose 2/4/8 with draft counters and round logs, SparkMan code 4/8/16
D=$(dirname "$0"); J=$D/../sm.jar; API=http://127.0.0.1:4100/api/fleet; L=$(cat $D/dev-launcher-id)
until grep -q "P4 BENCH 4X DONE\|FAILED" $D/../p4bench/run4x.log; do sleep 30; done; echo "[$(date +%T)] Sparks free"
st() { curl -s -b $J $API/launchers | python3 -c "import json,sys; print([l for l in json.load(sys.stdin) if l['id']=='$L'][0].get('state'))"; }
post() { curl -s -b $J -H 'content-type: application/json' -d '{}' $API/$1 >/dev/null; }
met() { curl -s http://<addr>:8888/metrics | python3 -c "
import sys; v={}
for l in sys.stdin:
    if l.startswith('tensorfold:') and ' ' in l and not l.startswith('#'):
        k,x=l.split()[:2]; v[k.split(':')[1]]=float(x)
print(' '.join(str(int(v.get(k,0))) for k in ('generation_tokens_total','mtp_drafted_total','mtp_accepted_total','decode_rounds_total')))"; }
rep() { read g0 d0 a0 r0 <<< "$1"; read g1 d1 a1 r1 <<< "$2"; python3 -c "
g,d,a,r=$g1-$g0,$d1-$d0,$a1-$a0,$r1-$r0
print(f'   drafted {d/max(r,1):.2f} per stream-round, accepted {100*a/max(d,1):.1f}%, tokens per stream-round {g/max(r,1):.2f}')"; }
for cfg in "$@"; do
  IFS='|' read b e tag <<< "$cfg"
  ssh sw-head "echo $b > ~/ripple-dev/current-bin; echo '$e' > ~/ripple-dev/current-env"
  post launchers/$L/start; t0=$(date +%s)
  until [ "$(st)" = serving ]; do s=$(st); case "$s" in failed|error|idle) [ $(( $(date +%s)-t0 )) -gt 120 ] && { echo "START FAILED $tag $s"; exit 1; };; esac; sleep 10; done
  echo "[$(date +%T)] [$tag] serving"
  for lv in 4 2 8; do
    n0=$(ssh sw-head "docker logs ripple-tf 2>&1 | grep -ac 'lanes-'")
    m0=$(met); python3 $D/../ripple-p4/prose16.py http://<addr>:8888/v1 Ripple-65B-Preview-4x $lv | sed "s/^/[$tag prose] /"; rep "$m0" "$(met)"
    ssh sw-head "docker logs ripple-tf 2>&1 | grep -a 'lanes-' | tail -n +$((n0+1))" > $D/probe-$tag-prose$lv.log
  done
  id=$(curl -s -b $J -H 'content-type: application/json' -d '{"scope":"replica","nodeId":"sw-head","deploymentId":"'$L'","config":{"kind":"decode","concurrency":[4,8,16],"maxTokens":1024,"promptType":"code"}}' $API/benchmarks | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  python3 $D/../ripple-p4/benchwait.py $id > $D/probe-code-$tag.txt; echo "[$tag] code 4/8/16 ($id): $(python3 -c "
import json; r=json.loads(open('$D/probe-code-$tag.txt').read().split(chr(10),1)[1]); print(' / '.join('%d: %.1f'%(x['concurrency'],x['aggregateTokS']) for x in r['levels']))")"
  post launchers/$L/stop; until [ "$(st)" = idle ]; do sleep 5; done
done
ssh sw-head "rm -f ~/ripple-dev/current-env"; echo "PROBE DONE"
