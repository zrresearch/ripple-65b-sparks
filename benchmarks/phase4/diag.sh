#!/bin/bash
# per build: 16 (and 8) prose streams and 16 code streams, with the server's draft counters read around each
D=$(dirname "$0"); J=$D/../sm.jar; API=http://127.0.0.1:4100/api/fleet; L=$(cat $D/dev-launcher-id)
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
print(f'   tokens {g}, rounds {r}, drafted {d} ({d/max(r,1):.2f} a round per stream-round), accepted {a} ({100*a/max(d,1):.1f}%), tokens a stream-round {g/max(r,1):.2f}')"; }
for b in "$@"; do
  ssh sw-head "echo $b > ~/ripple-dev/current-bin"; post launchers/$L/start
  until [ "$(st)" = serving ]; do sleep 10; done
  for lv in 16 8; do m0=$(met); python3 $D/../ripple-p4/prose16.py http://<addr>:8888/v1 Ripple-65B-Preview-4x $lv | sed "s/^/[$b prose] /"; rep "$m0" "$(met)"; done
  python3 - <<'PY' > /dev/null
PY
  post launchers/$L/stop; until [ "$(st)" = idle ]; do sleep 5; done
done
echo DIAG DONE
