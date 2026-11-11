# Ripple-65B on DGX Sparks

Building a four-Spark serving recipe for [ricursiveAI/Ripple-65B-Preview](https://huggingface.co/ricursiveAI/Ripple-65B-Preview)
(65B dense, 1M context, Apache-2.0), starting from the community two-Spark TensorFold path, with our own EXL3 packs.

The write-up is `paper/ripple-paper.html`, a self-contained page.

## Status

| Phase | State |
|---|---|
| 1. Reproduce two Sparks (own EXL3 5.0 bpw pack, TensorFold `ricursive-tp2-dflash2`) | under way: downloads |
| 2. Generalize the TP path from two ranks to two or four | not started |
| 3. Four Sparks on the QSFP switch | waits for the four-Spark group |
| 4. Speed: 16 streams, 1M context, DFlash2 | not started |
| 5. Publish recipe, packs, upstream changes | not started |

## Layout

| Path | Contents |
|---|---|
| `paper/ripple-paper.html` | The paper |
| `provenance/` | Download script, checksum verification, library index records |
| `config/` | Conversion and serving settings |
| `logs/` | Conversion and serving logs |
| `data/`, `benchmarks/` | Measurements, added as runs complete |
| `tools/` | Scripts, including `scrub-for-github.sh` (makes the GitHub copy) |
