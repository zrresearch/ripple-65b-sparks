#!/usr/bin/env bash
# Phase 4 step 2: TensorFold PR #2475 head (CUDA ricursive family + DFlash2 drafter, stacked on #2302), built for GB10
# in the 2x recipe's ripple-zig-build image. Weights: NVFP4 release @99eea447 from the models library.
set -euo pipefail
cd ~/ripple-nvfp4
HEAD=409d34ee2
[[ -d TensorFold/.git ]] || git clone -q https://github.com/ashhart/TensorFold.git TensorFold
cd TensorFold && git fetch -q origin pull/2475/head:pr2475 && git checkout -q -f pr2475
[[ "$(git rev-parse --short=9 HEAD)" == "$HEAD" ]] || { echo "head is $(git rev-parse --short=9 HEAD), not $HEAD"; exit 1; }
cat .zig-version 2>/dev/null || true
mkdir -p ~/.cache/ripple-nvfp4/zig
echo "compile $(date -Is)"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e ZIG_GLOBAL_CACHE_DIR=/zc -v ~/.cache/ripple-nvfp4/zig:/zc \
  -v "$PWD:/w" -w /w ripple-zig-build:0.17.0 bash -c \
  "git config --global --add safe.directory /w; zig build native -Doptimize=fast -Dnvcc=\$(which nvcc) -Dsm=121"
ls -la zig-out/native/bin/tensorfold-native && echo "BUILT $(date -Is)"
