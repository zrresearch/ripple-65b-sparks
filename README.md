# Ripple-65B on DGX Sparks

Building a four-Spark serving recipe for [ricursiveAI/Ripple-65B-Preview](https://huggingface.co/ricursiveAI/Ripple-65B-Preview)
(65B dense, 1M context, Apache-2.0), starting from the community two-Spark TensorFold path, with our own EXL3 packs.

The write-up is `paper/ripple-paper.html`, a self-contained page.

## Status

| Phase | State |
|---|---|
| 1. Reproduce two Sparks (own EXL3 5.0 bpw pack, TensorFold `ricursive-tp2-dflash2`) | done: speed, 1M context and drafted output reproduce |
| 2. Generalize the TP path from two ranks to two or four | done: two ranks byte-identical to the original |
| 3. Four Sparks on the QSFP switch | done: byte-identical to two Sparks, 1.5-1.75x faster; Tier 2 quality suite run |
| 4. Speed: 16 streams, 1M context, DFlash2 | done: prompt reading about 2x, code decode 229 tok/s at 16 streams; quality unchanged |
| 5. Publish recipe, packs, upstream changes | not started |

The recipe is the two-Spark [ripplespark-2dgx](https://github.com/ajensenwaud/ripplespark-2dgx) recipe plus the patches
in `recipe-patches/`: `0001`-`0004` apply to the recipe with `git am` (four Sparks, per-rank RoCE devices, a start fix,
and Phase 4), and `tensorfold-0010`-`0015` are the engine patches it applies to TensorFold.

## Layout

| Path | Contents |
|---|---|
| `paper/ripple-paper.html` | The paper |
| `provenance/` | Download script, checksum verification, library index records |
| `config/` | Conversion and serving settings |
| `logs/` | Conversion and serving logs |
| `data/`, `benchmarks/` | Measurements by phase; `benchmarks/phase4/RESULTS.md` has every Phase 4 run |
| `recipe-patches/` | Patches to the two-Spark recipe and to TensorFold |
| `tools/` | Scripts, including `scrub-for-github.sh` (makes the GitHub copy) |
