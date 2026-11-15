#!/usr/bin/env bash
# start.sh : serve Ripple-65B-Preview on two or four Sparks (TensorFold's native server, TP=2 or TP=4), run ON the head
# (rank 0). Ranks 1.. (`tf-ricursive follow`) start on the workers first, in WORKERS order, then rank 0
# (`tensorfold-native serve`) here on :$PORT; all in Docker (ripple-tf-follow, ripple-tf) from $IMAGE with the built
# zig-out mounted. Waits for /v1/models and sends one warm-up chat. Takes ~/ripple/gpu.lock on every node (kept while
# serving; ./stop.sh drops it).
#   scripts/start.sh                         1 stream x 1,048,576 tokens (the default: the model's served window)
#   STREAMS=4 CONTEXT=262144 scripts/start.sh  4 streams x 256K
# Env: PACK (5.0 | 6.0), PORT, BIN (a zig-out), MEM_RESERVE_GIB, PROMPT_CACHE_GIB, GRAPHS, ROCE, NAME (container),
#      DRAFTER (1: DFlash2 drafter from DRAFT_DIR), COPIES (0: no prompt-copy drafts), SERVE_ARGS (extra serve flags,
#      e.g. --loop-guard).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh
need_pair
BIN=${BIN:-$ZIG_DIR/zig-out}
NAME=${NAME:-ripple-tf}
LOCK=$HOME/ripple/gpu.lock
TAG="serve $NAME :$PORT $(date -Is)"
[[ -x $BIN/native/bin/tensorfold-native && -x $BIN/bin/tf-ricursive ]] || die "no build in $BIN (scripts/zig_build.sh native ricursive-cuda)"
[[ -f $MODEL_DIR/config.json ]] || die "no pack at $MODEL_DIR"
for W in "${W_LIST[@]}"; do ssh -n "$W" "test -f $MODEL_DIR/config.json" || die "$W has no pack at $MODEL_DIR"; done
ss -ltn "( sport = :$PORT )" | grep -q LISTEN && die "port $PORT is taken"
mkdir -p "$(dirname "$LOCK")"
( set -o noclobber; echo "$TAG" > "$LOCK" ) 2> /dev/null || die "head GPU busy: $(cat "$LOCK")"
LOCKED=()
fail() {
  docker rm -f "$NAME" > /dev/null 2>&1 || true
  for W in "${LOCKED[@]}"; do ssh -n "$W" "docker rm -f $NAME-follow > /dev/null 2>&1; rm -f ~/ripple/gpu.lock"; done
  rm -f "$LOCK"; die "$@"
}
for W in "${W_LIST[@]}"; do
  ssh -n "$W" "mkdir -p ~/ripple; ( set -o noclobber; echo '$TAG' > ~/ripple/gpu.lock ) 2> /dev/null" || fail "$W GPU busy: $(ssh -n "$W" cat ~/ripple/gpu.lock)"
  LOCKED+=("$W")
done
# the same build on every node
D=$(dirname "$BIN")
a=$(sha256sum "$BIN/native/bin/tensorfold-native" "$BIN/bin/tf-ricursive" | cut -c1-16 | tr '\n' ' ')
for W in "${W_LIST[@]}"; do
  ssh -n "$W" "mkdir -p ${D#$HOME/}"; rsync -a "$BIN" "$W:${D#$HOME/}/"
  b=$(ssh -n "$W" "sha256sum $BIN/native/bin/tensorfold-native $BIN/bin/tf-ricursive" | cut -c1-16 | tr '\n' ' ')
  [[ $a == "$b" ]] || fail "builds differ: head $a, $W $b"
done
# four ranks with ROCE=1: the small gathers on fabric/tp's multirank wire, if the build has its mailbox kernel (else NCCL)
WIRE=""
if (( WORLD > 2 )) && [[ $ROCE == 1 ]]; then
  if [[ -f $BIN/lib/tp_mailbox.fatbin ]]; then
    WIRE="-e TF_TP_MASTER=$MASTER -e TF_TP_PORT=$TP_WIRE_PORT -e TF_TP_KERNEL_IMAGE=$BIN/lib/tp_mailbox.fatbin"
  else
    log "no $BIN/lib/tp_mailbox.fatbin: NCCL carries every gather (scripts/zig_prepare.sh builds it)"
  fi
fi
read -ra RH <<< "$RANK_HCAS"
hcas() { local h=${RH[$1]:--}; [[ $h == - ]] && h=$NCCL_HCAS; echo "$h"; } # RANK: its RoCE devices
run_args() { # RANK: every rank's container settings (NCCL over the CX7 RoCE link, as MiMo's recipe)
  echo "--gpus all --ipc=host --network host --device /dev/infiniband --cap-add IPC_LOCK --ulimit memlock=-1" \
    "--user $(id -u):$(id -g) -e HOME=/tmp -v $MODEL_DIR:$MODEL_DIR:ro -v $D:$D:ro" \
    "-e NCCL_COMM_ID=$MASTER:$TP_PORT -e NCCL_SOCKET_IFNAME=$NCCL_IFNAME -e NCCL_IB_HCA=$(hcas "$1")" \
    "-e NCCL_IB_GID_INDEX=$NCCL_GID -e TF_ROCE_GID_INDEX=$NCCL_GID -e NCCL_MIN_NCHANNELS=4 -e NCCL_MAX_NCHANNELS=4" \
    "-e TF_RICURSIVE_RANK=$1 -e TF_RICURSIVE_WORLD=$WORLD -e TF_RICURSIVE_CONTEXT=$CONTEXT -e TF_RICURSIVE_SLOTS=$STREAMS" \
    "-e TF_RICURSIVE_GRAPHS=$GRAPHS -e TF_RICURSIVE_ROCE=$ROCE -e TENSORFOLD_MEMORY_RESERVE_GIB=$MEM_RESERVE_GIB $WIRE ${EXTRA_ENV:-}"
}
mkdir -p logs
[[ $COPIES == 0 ]] && EXTRA_ENV="${EXTRA_ENV:-} -e TF_RICURSIVE_COPY_DRAFTS=0"
# the drafter's share on every follower too (cuda_draft.zig cuts it over the ranks as the target)
d1=""; [[ $DRAFTER == 1 ]] && d1="-v $DRAFT_DIR:$DRAFT_DIR:ro -e TF_RICURSIVE_DRAFTER=$DRAFT_DIR"
r=1
for W in "${W_LIST[@]}"; do
  log "rank $r of $WORLD on $W: $(basename "$MODEL_DIR"), $STREAMS x $CONTEXT tokens"
  ssh -n "$W" "docker rm -f $NAME-follow > /dev/null 2>&1; docker run -d --name $NAME-follow $(run_args $r) $d1 \
    --entrypoint $BIN/bin/tf-ricursive $IMAGE:latest $MODEL_DIR follow > /dev/null" || fail "rank $r did not start"
  r=$((r + 1))
done
log "rank 0 here on :$PORT"
pc=${PROMPT_CACHE_GIB:+--prompt-cache-gib $PROMPT_CACHE_GIB}
dm=""; if [[ $DRAFTER == 1 ]]; then [[ -f $DRAFT_DIR/config.json ]] || fail "no drafter at $DRAFT_DIR"; dm="-v $DRAFT_DIR:$DRAFT_DIR:ro"; pc="$pc --drafter $DRAFT_DIR"; fi
# shellcheck disable=SC2046,SC2086
# PROFILE (temporary, Phase 4): rank 0 under an Nsight Systems session; start/stop it with docker exec nsys start/stop --session=rp
NS=/opt/nvidia/nsight-systems/2025.3.2/target-linux-sbsa-armv8/nsys; mkdir -p $HOME/ripple-prof
docker run -d --name "$NAME" $(run_args 0) $dm -v /opt/nvidia/nsight-systems:/opt/nvidia/nsight-systems:ro -v $HOME/ripple-prof:/prof \
  --entrypoint $NS "$IMAGE:latest" launch --session-new=rp --trace=cuda,nvtx --cuda-graph-trace=node "$BIN/native/bin/tensorfold-native" \
  serve "$MODEL_DIR" --host "$HOST" --port "$PORT" --name "$SERVED_NAME" --parallel "$STREAMS" --context "$CONTEXT" \
  --max-tokens "$MAX_TOKENS" $pc ${SERVE_ARGS:-} > /dev/null || fail "rank 0 did not start"
{ echo "# $(date -Is) scripts/start.sh"; echo "pack $MODEL_DIR"; echo "build $BIN $a"; echo "world $WORLD: head ${W_LIST[*]}"
  echo "rank0 $(run_args 0)"; echo "serve --parallel $STREAMS --context $CONTEXT --max-tokens $MAX_TOKENS $pc ${SERVE_ARGS:-}"; } > logs/serve-config.txt
mem() { awk '/MemAvailable/{printf "%.1f", $2/1048576}' /proc/meminfo; }
for i in $(seq 1 360); do
  if curl -fsS -m 3 "http://127.0.0.1:$PORT/v1/models" > /dev/null 2>&1; then
    log "up after $((i * 5)) s"
    log "engine: $(docker logs "$NAME" 2>&1 | grep -m1 'CUDA sm_' | sed 's/^\[tensorfold\] //' | cut -c1-400)"
    m="head $(mem)"; for W in "${W_LIST[@]}"; do m="$m, $W $(ssh -n "$W" "awk '/MemAvailable/{printf \"%.1f\", \$2/1048576}' /proc/meminfo")"; done
    log "MemAvailable GiB: $m"
    out=$(curl -fsS -m 600 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' \
      -d "{\"model\": \"$SERVED_NAME\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in five words.\"}], \"max_tokens\": 512, \"temperature\": 0}") \
      || fail "warm-up request failed: docker logs $NAME"
    log "warm-up: $(python3 -c 'import json,sys; j=json.loads(sys.argv[1]); print(repr(j["choices"][0]["message"].get("content"))[:200], j["usage"])' "$out")"
    log "serving $SERVED_NAME at http://$(hostname):$PORT/v1 on $WORLD Sparks"
    exit 0
  fi
  docker inspect -f '{{.State.Running}}' "$NAME" 2> /dev/null | grep -q true || { docker logs --tail 30 "$NAME"; fail "rank 0 exited"; }
  if (( i % 6 == 0 )); then
    r=1
    for W in "${W_LIST[@]}"; do
      ssh -n "$W" "docker inspect -f '{{.State.Running}}' $NAME-follow 2> /dev/null" | grep -q true || { ssh -n "$W" "docker logs --tail 30 $NAME-follow"; fail "rank $r exited on $W"; }
      r=$((r + 1))
    done
  fi
  sleep 5
done
fail "not up after 30 min: docker logs $NAME"
