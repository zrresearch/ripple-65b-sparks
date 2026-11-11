#!/usr/bin/env bash
# Ricursive Ripple-65B-Preview (BF16, ~130 GB) and its DFlash2 drafter (BF16, ~8 GB) at pinned revisions, for a local
# EXL3 conversion and a 2- then 4-Spark TensorFold recipe; plus the ajensenwaud EXL3 5.0bpw pack (~39 GB), the
# 2-Spark reference build to compare ours against. Into <library>/Ricursive/hub.
set -uo pipefail
HF=$HOME/.local/bin/hf
C=<library>/Ricursive/hub
mkdir -p $C
echo "start $(date -Is)"
for spec in ricursiveAI/Ripple-65B-Preview@b172323ffd63e62de9ce1ba3830dfffe493c7671 \
            ricursiveAI/Ripple-65B-Preview-DFlash2@35609b3be3dd08a822b3ba1257c1ea5dd6f87632 \
            ajensenwaud/Ripple-65B-Preview-exl3-5.0bpw@1d260f752b753d2b17571de237029b5e2251db07; do
  repo=${spec%@*}; rev=${spec#*@}
  echo "get $repo @ $rev $(date -Is)"
  $HF download $repo --revision $rev --cache-dir $C >/dev/null || { echo "FAILED $repo $(date -Is)"; exit 1; }
  $HF cache verify $repo --revision $rev --cache-dir $C --fail-on-missing-files 2>&1 | tail -2
done
echo "ALL DONE $(date -Is)"
