#!/usr/bin/env bash
# SparkMan launcher entry (temporary, Phase 4 step 2): Ripple-65B-Preview NVFP4 on ONE GB10, TensorFold PR #2475 head
# 409d34ee2 (CUDA ricursive family + DFlash2 drafter). CONTEXT=131072 gives 4 streams, 32768 gives 8 (the recipe).
set -euo pipefail
CONTEXT=${CONTEXT:-32768} PORT=8888 NAME=ripple-nvfp4 SERVED=Ripple-65B-Preview-NVFP4
M=$HOME/models/Ripple-65B-Preview-NVFP4 DR=$HOME/models/Ripple-65B-Preview-DFlash2 B=$HOME/ripple-nvfp4/TensorFold/zig-out
mkdir -p $HOME/ripple-nvfp4/logs
docker rm -f $NAME >/dev/null 2>&1 || true
docker run -d --name $NAME --gpus all --ipc=host --network host --user $(id -u):$(id -g) -e HOME=/tmp \
  -v $M:$M:ro -v $DR:$DR:ro -v $B:$B:ro --entrypoint $B/native/bin/tensorfold-native ripple-tf:latest \
  serve $M --host <addr> --port $PORT --name $SERVED --context $CONTEXT --drafter $DR >/dev/null
echo "$(date -Is) started context=$CONTEXT" >> $HOME/ripple-nvfp4/logs/launch.log
for i in $(seq 1 180); do
  curl -sf http://<addr>:$PORT/v1/models >/dev/null && { echo "serving"; exit 0; }
  docker ps -q -f name=^$NAME$ | grep -q . || { docker logs --tail 30 $NAME; exit 1; }
  sleep 5
done
echo "not serving after 15 min"; docker logs --tail 30 $NAME; exit 1
