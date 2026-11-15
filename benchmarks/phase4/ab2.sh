#!/bin/bash
# Fix 2 on 4 Sparks: pfdense + 512-row chunks (build pfd512) vs fix 1 alone (build 0011); goldens, prefill, decode
D=$(dirname "$0")
start() { ssh sw-head 'cd ~/ripple-4x && scripts/stop.sh >/dev/null 2>&1; BIN=$HOME/ripple-dev/'"$1"' STREAMS=1 CONTEXT=1048576 SERVED_NAME=Ripple-65B-Preview EXTRA_ENV="'"$2"'" timeout 900 scripts/start.sh > /tmp/rp-start.log 2>&1; tail -1 /tmp/rp-start.log'; }
dec() { python3 - <<'PY'
import json,time,urllib.request
b={"model":"Ripple-65B-Preview","messages":[{"role":"user","content":"Write a Python function that merges overlapping intervals, with tests."}],"max_tokens":512,"temperature":0}
out=[]
for _ in range(2):
    t=time.time(); r=json.load(urllib.request.urlopen(urllib.request.Request("http://<addr>:8888/v1/chat/completions",json.dumps(b).encode(),{"Content-Type":"application/json"}),timeout=600))
    out.append(r["usage"]["completion_tokens"]/(time.time()-t))
print("code decode 1 stream: "+" / ".join("%.1f"%x for x in out)+" tok/s (incl. prompt)")
PY
}
for cfg in "zig-out-pfd512|" "zig-out-pfd512|-e TF_RICURSIVE_PFD=0" "zig-out-0011|"; do
  b=${cfg%%|*}; e=${cfg#*|}; start $b "$e"; tag="[$b ${e:-default}]"
  python3 $D/golden.py http://<addr>:8888 $D/g-${b}-${e:+nopfd}.json >/dev/null && echo "$tag goldens vs phase 3:" && python3 $D/golden.py --compare $D/tp4x4-drafted.json $D/g-${b}-${e:+nopfd}.json
  echo "$tag $(python3 $D/pf8k.py 7600)"; echo "$tag $(python3 $D/pf8k.py 30000)"; echo "$tag $(dec)"
done
ssh sw-head 'cd ~/ripple-4x && scripts/stop.sh 2>&1 | tail -1'; echo "AB2 DONE"
