#!/usr/bin/env bash
# Perplexity (wiki2, 64 x 2048) for both 5.0 packs, then top-token agreement and KL vs BF16 (96 x 2048), as the recipe reports.
set -u
M=$HOME/models; O=$HOME/ripple-2x/runs/quality
run(){ docker run --rm --gpus all --ipc=host --shm-size 16g -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
  -v $M:$M:ro -v $HOME/.cache/ripple-tf:/root/.cache --entrypoint python3 ripple-tf:latest "$@"; }
for p in Ripple-65B-Preview-exl3-5.0bpw-ajensenwaud Ripple-65B-Preview-exl3-5.0bpw; do
  run /opt/exllamav3/eval/ppl.py -m $M/$p -r 64 > $O/ppl-$p.log 2>&1
done
for p in Ripple-65B-Preview-exl3-5.0bpw-ajensenwaud Ripple-65B-Preview-exl3-5.0bpw; do
  run /opt/exllamav3/eval/model_diff.py -ma $M/Ripple-65B-Preview -mb $M/$p -r 96 > $O/diff-$p.log 2>&1
done
echo done > $O/all.done
