#!/bin/bash
D=$(dirname "$0")
for env in "" "-e NCCL_PROTO=Simple" "-e NCCL_PROTO=Simple -e NCCL_MIN_NCHANNELS=8 -e NCCL_MAX_NCHANNELS=8" "-e NCCL_PROTO=LL128"; do
  ssh sw-head 'cd ~/ripple-4x && scripts/stop.sh >/dev/null 2>&1; STREAMS=8 CONTEXT=262144 SERVED_NAME=Ripple-65B-Preview-4x EXTRA_ENV="'"$env"'" timeout 900 scripts/start.sh > /tmp/rp-start.log 2>&1; tail -1 /tmp/rp-start.log'
  echo "[${env:-recipe default: LL chosen by NCCL, 4 channels}] $(python3 $D/pf8k.py 7600)"
done
echo "SWEEP DONE"
