# Phase 4 measurements

All runs 2026-11-13/14 on our fleet. Ripple-65B-Preview, the reference EXL3 5.0 bpw pack, DFlash2 drafter on, unless noted.
Raw outputs in `raw/` (SparkMan benchmark ids in `raw/sparkman-bench-ids.txt`).

Test definitions:
- **SparkMan prefill**: one cold request per size, a salted filler prompt, `max_tokens` 1; tok/s = prompt tokens / TTFT.
- **SparkMan code decode**: SparkMan's code prompts, temperature 0, up to 1,024 tokens, N streams at once; total tok/s.
- **Prose** (`prose16.py`): a story prompt, temperature 0.7, thinking on, 1,024 tokens, N at once, median of 3; total tok/s.
- **pf8k** (`pf8k.py`): one cold salted filler prompt of ~7.6K or ~30K tokens, `max_tokens` 1, two repeats; tok/s.

## Builds

| Label | Engine | Sparks | Notes |
|---|---|---|---|
| 4x baseline | TensorFold v1.2.3 + #2522/#2523 + our 0010 (tree 326a0a51) | 4, switch-dell | launcher default 8 streams x 256K |
| 2x baseline | same build | 2, pair-pny | launcher default 1 stream x 1M |
| 1x NVFP4 | TensorFold PR #2475 head 409d34ee2 | 1, pny-head | NVFP4 release @99eea447; 4 x 128K (prefill), 8 x 32K (decode) |
| 4x + 0011 | baseline + `tensorfold-0011-ricursive-row-scatter.patch` | 4 | dev build f482fadc (sha256 prefix) |

## Prefill scaling (SparkMan prefill, tok/s)

| Prompt | 1x NVFP4 | 2x baseline | 4x baseline | 4x / 2x |
|---:|---:|---:|---:|---:|
| 4K | 494 | 415 | 572 | 1.38x |
| 8K | 497 | 413 | 572 | 1.39x |
| 16K | 491 | 408 | 564 | 1.38x |
| 32K | 473 | 399 | 546 | 1.37x |
| 64K | 433 | 378 | 509 | 1.35x |
| 123K / 131K | 374 | 344 | 454 | 1.32x |

## Decode (total tok/s)

| Streams | 4x code | 4x code (16-stream config) | 4x prose | 4x prose (16-stream config) | 1x NVFP4 code | 1x NVFP4 prose |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 64.2 | 70.6 | 27.5 | 26.9 | 22.0 | 7.5 |
| 2 | 108.8 | 98.1 | 48.0 | 47.3 | 42.8 | 14.4 |
| 4 | 125.8 | 127.4 | 73.3 | 76.4 | 69.9 | 27.2 |
| 8 | 115.4 | 113.5 | 89.1 | 91.5 | 100.7 | 47.6 |
| 16 | - | 156.4 | - | 172.6 | - | - |

16-stream config: STREAMS=16 CONTEXT=131072.

## Where 4x prefill time goes (nsys, rank 0, one cold 7,647-token prompt, 584 tok/s under the profiler)

| Category | GPU time | Share |
|---|---:|---:|
| EXL3 matmuls (tf_exl3_mpg_*, rotations) | 7.46 s | 57.3% |
| NCCL AllGather (RING_LL) of fp32 partials | 4.20 s | 32.3% |
| Attention | 0.58 s | 4.5% |
| Other (norms, rank sum, glue) | 0.78 s | 6.0% |

## NCCL settings sweep (4x baseline, pf8k ~7.6K)

| Setting | tok/s |
|---|---:|
| recipe default (NCCL picks LL, 4 channels) | 580 / 577 |
| NCCL_PROTO=Simple | 578 / 576 |
| NCCL_PROTO=Simple, 8 channels | 588 / 585 |
| NCCL_PROTO=LL128 | 514 / 513 |

## Fix 1: row reduce-scatter (patch 0011), before / after

Same dev build, 4 Sparks, 1 stream x 1M, `TF_RICURSIVE_SCATTER=0` = before.

| pf8k | Before (gather) | After (scatter) | Change |
|---:|---:|---:|---:|
| ~7.6K tokens | 571 / 557 | 643 / 643 | +14% |
| ~30K tokens | 534 / 542 | 610 / 612 | +13.5% |

Correctness: greedy replies to the four golden prompts (code, tool call, chat, 7,240-token lookup), DFlash2 on, byte-identical to
Phase 3's four-rank goldens (`../phase3/tp4x4-drafted.json` vs `scatter-drafted.json`).

## Fix 2: pfdense prompt projections + bigger prompt chunks (patch 0012)

### Kernel microbenchmark (one GB10, one layer, a TP=4 rank's slices of Ripple's 8 projections; `mb.py`, `mb2.py`)

| Rows | Trellis kernel, 128-row blocks (before) | Decode to fp16 + GEMM (ExLlamaV3) | pfdense incl. rot_in (chosen) |
|---:|---:|---:|---:|
| 128 | 30.7 TFLOPS | 12.1 | 38.9 |
| 512 | 30.3 | 34.1 | 61.1 |
| 1024 | 30.0 | 53.1 | 63.9 |
| 2048 | 29.3 | 68.1 | 67.6 |
| 4096 | - | - | 67.0 |

pfdense output vs ExLlamaV3's: relative difference 5.3e-4.

### Four Sparks, before / after (pf8k, 1 stream x 1M; `ab2.sh`, raw/fix2-ab-4x.log)

| Build | ~7.6K tokens | ~30K tokens | Goldens vs Phase 3 |
|---|---:|---:|---|
| baseline (scatter off; from fix 1 table) | 571 / 557 | 534 / 542 | 4/4 identical |
| + 0011 (scatter) | 641 / 640 | 610 / 610 | 4/4 identical |
| + 0012 at 512 rows, pfdense off | 680 / 679 | 664 / 664 | 4/4 identical |
| + 0012 at 512 rows, pfdense on | 1,000 / 997 | 966 / 965 | 3/4 identical; coding differs from char 1,481 of 1,500 (closing prose) |
| + 0012 at 1,024 rows (final) | **1,052 / 1,050** | **1,016 / 1,014** | same bytes as 512 rows |

Prefill vs the original baseline: about **1.85x** at 7.6K, **1.88x** at 30K.

One-stream code decode (512 tokens, incl. prompt; two runs): 0011 64.2 / 61.9, 0012 at 512 rows 62.0 / 60.4 (pfdense on) and 62.4 / 61.0
(off). Within noise of two runs; to be measured properly with SparkMan's decode test.

### Quality (one GB10, tf-ricursive long, 16,384 WikiText-2 test tokens; raw/nll16k)

| Run | Perplexity | Top-1 vs A |
|---|---:|---:|
| A: baseline build (trellis, 128-row chunks) | 6.9793 | - |
| B: 0012 build, pfdense off (512 rows) | 6.9793, NLL bit-identical to A | 100% |
| C: 0012 build, pfdense on (512 rows) | 6.9802 (+0.013%) | 99.66% (56 tokens differ) |

Per-token NLL difference C - A: mean +0.00013, mean abs 0.0079, 99th percentile abs 0.071.
For scale: the 5.0 bpw pack's perplexity is 0.27% above BF16 (Table 4). One GB10 prompt speed in the same runs: 226 (A), 224 (B), 320 (C) tok/s.

### Where 4x prefill time goes now (nsys, rank 0, two cold ~7.6K prompts, raw/kern-pfd1024.csv)

| Category | Share | Before fixes |
|---|---:|---:|
| pfdense prompt GEMM (68 TFLOPS) | 50.5% | 57.3% (trellis, ~33 TFLOPS) |
| NCCL send/recv (row scatter) | 28.0% | 32.3% (all-gather) |
| Other (norms, glue) + rot_in | 15.5% | 6.0% |
| Attention | 6.0% | 4.5% |

## Fix 2b: exchange overlapped with compute (patch 0013)

Prompt calls of 256+ rows run o_proj through post_ffn in two row halves; each half's row-scatter sum runs on a second
(highest-priority) stream while the other half computes. Same build, four Sparks, 1 stream x 1M, pf8k.

| Build | ~7.6K tokens | ~30K tokens | Goldens |
|---|---:|---:|---|
| 0011 + 0012 + 0013, `TF_RICURSIVE_OVERLAP=0` | 1,038 / 1,051 | 1,015 / 1,015 | - |
| 0011 + 0012 + 0013 (overlap on) | **1,175 / 1,172** | **1,118 / 1,114** | byte-identical to the 0012 build (4/4) |

Cumulative prefill vs the original baseline (571 / 557 at 7.6K, 534 / 542 at 30K): about **2.08x** at 7.6K and **2.07x** at 30K.

## Fix 3: multi-stream decode (patch 0014)

Four Sparks, 16 streams x 128K, DFlash2 on; SparkMan code decode (T 0, 1,024 tokens) and prose (T 0.7, median of 3). Raw:
raw/fix3-decode-*.log, diagnostics raw/fix3-diagnostics.log, profile raw/r64-prose16.nsys-rep.

Cause: a shared round held at most 16 rows over all streams (`round_rows`), so 8 streams verified one draft each at most and
16 none, while a 16-row window costs 75 ms against 59 ms for one row.

| Step | Code 1 / 2 / 4 / 8 / 16 | Prose 16 | Prose 8 |
|---|---|---:|---:|
| before (0013 build) | 70.1 / 106.4 / 125.7 / 119.8 / 148.9 | 170.0 | 90.1 |
| 64-row rounds, shared widths timed | 70.1 / 105.9 / 151.6 / 189.2 / 190.2 | 116.0 | 90.3 |
| + RoCE wire limit 1 MiB (env, no effect; not kept) | - | 114.5 | 91.3 |
| + one drafter pass for all streams | - | 136.6 | 97.3 |
| + drafter pass timed and priced (hold_costs) | - | 133.7 | 96.9 |
| + batched absorbs (final 0014) | **69.6 / 107.4 / 153.3 / 194.0 / 228.6** | 146.3 | **100.9** |

Final prose 1 / 2 / 4 / 8 / 16: 26.2 / 46.6 / 74.8 / 100.9 / 146.3 (before: 26.9 / 47.9 / 70.7 / 90.1 / 170.0).
Greedy goldens byte-identical at every step.

Draft counters (server /metrics) for prose at 16 streams: before, 0 drafts (1.00 token a stream-round, ~96 ms a round);
64-row rounds, 2.19 drafts a stream-round at 36.9% kept (1.81 tokens, ~249 ms); final, 1.55 at 43.2% (1.67 tokens, ~184 ms).
Drafter pass on four GB10s: 14.6 / 22.1 / 54.6 ms for 1 / 4 / 16 streams (depth 15). At 16 sampled streams drafting
still lost to plain rounds (0.145 vs 0.167 tokens/ms): fixed in 0015, below.

## Fix 3b: drafter pass priced in shared rounds (patch 0015)

Same setup; one binary (zig-out-price), A/B by `TF_HOLD_SHARED=0`, per-round log by `TF_LANES_PRICE_LOG=1` (not kept in the
patch). Raw: raw/fix3b-price.log, raw/fix3b-code16.log, per-round logs raw/fix3b-rounds/, scripts price.sh and code16.sh.

Cause: Ripple's shared rounds are budgeted by `shared_drafts.budgets`, not `rule.budgets` (the drafter sets
`allocate_shared_drafts`), and it priced every option, drafting none included, with `overheadMs` = fixed share + the
measured drafter pass. 0014's hold pricing went into `rule.budgets`, so it never applied here. Round log, 16 prose streams,
old pricing: all 1,547 full rounds drafted, 45.4 rows, 27.9 tokens kept, 186.7 ms (0.150 tokens/ms), with a 76.9 ms overhead
charged to plain as well (of it 52.1 ms the drafter pass). Fix: with hold costs, `fixedMs` plus the hold table, so the pass
is priced by the streams that draft and their deepest chain.

| | Prose 16 | Prose 8 | Code 1 / 2 / 4 / 8 / 16 | Code 16 (two more runs) |
|---|---:|---:|---|---|
| old pricing (`TF_HOLD_SHARED=0`) | 143.4 | 103.2 | 67.3 / 97.5 / 151.4 / 201.0 / 228.9 | 221.3 / 237.2 |
| 0015 | **190.3** | **112.0** | 65.2 / 107.7 / 153.6 / 200.3 / 217.2 | 221.1 / 238.4 |

Code is unchanged within run-to-run spread (16 streams spans 217-238 in either setting); every full code round drafts at
both (fixed: 63.9 rows, 55.0 tokens, 196.5 ms, 0.28 tokens/ms). Prose at 16 with 0015: 2,860 plain rounds (16 rows, 83.9 ms,
0.191 tokens/ms) and 72 drafted (63.1 rows, 38.5 tokens, 190.9 ms, 0.202 tokens/ms); learned fixed share 8.8 ms, matching
a plain round's 83.9 - 75.0 ms forward. Prose 16 is now 12% above the pre-0014 170.0. Goldens identical to the 0012-0014
builds (coding still differs from phase 3 at char 1481, the known pfdense change).

## Final four-Spark measurements: the recipe build (patches 0001-0015, tree de18a25b)

Built by the recipe's own `scripts/zig_prepare.sh` on the head and copied to the workers. Raw: raw/final-4x/ (run4x.sh,
p4-4x.sh). Part A served by the recipe's start.sh (Phase 3's configs); part B by the 16 x 128K test launcher.

Goldens vs Phase 3 (`phase3/tp4x4-*.json`): plain, drafted and four streams at once each 3 of 4 identical; coding differs in
all three (the pfdense change, near its end, as in fix 2).

| One stream, decode_bench (tok/s, mean of 2) | Phase 3 | Phase 4 |
|---|---:|---:|
| coding / tool call / chat, plain | 17.7 / 19.1 / 17.4 | 17.64 / 19.06 / 17.37 |
| coding / tool call / chat, DFlash2 | 55.7 / 50.5 / 25.6 | 57.39 / 50.99 / 25.12 |

1M retrieval (Phase 1's 1,015,070-token prompt, 1 x 1M, DFlash2): first token after 2,840 s (47.3 min), 357.4 tok/s; answer
correct (7319-KESTREL-0442); decode after it 11.63 tok/s. Two Sparks, Phase 1: 6,484 s, 156.6 tok/s, 5.22 tok/s.

| SparkMan prefill | 4K | 8K | 16K | 32K | 64K |
|---|---:|---:|---:|---:|---:|
| 4x baseline | 572 | 572 | 564 | 546 | 509 |
| recipe build | 1,042 | 1,124 | 1,113 | 1,109 | 1,043 |

128K skipped (the test launcher's window is 131,072 tokens; the baseline ran at 256K windows).

| Streams | Code, baseline (16 x 128K) | Code, recipe | Prose, baseline (16 x 128K) | Prose, recipe |
|---:|---:|---:|---:|---:|
| 1 | 70.6 | 67.8 | 26.9 | 25.7 |
| 2 | 98.1 | 105.5 | 47.3 | 47.9 |
| 4 | 127.4 | 155.7 | 76.4 | 65.8 (repeats 72.8-75.5, below) |
| 8 | 113.5 | 198.3 | 91.5 | 113.2 |
| 16 | 156.4 | 228.8 | 172.6 | 188.9 |

## The 4-stream prose figure (65.8): not reproduced

Hypothesis checked: under 0015 a stream priced out of drafting can stay plain, since `shared_drafts.budgets` has no probe and a
stream's estimates move only in drafted rounds. Build zig-out-probe added a per-stream budget log and a probe (a plain stream
drafts one after a doubling run of plain rounds, as `rule.budgets` does under plain_guard; `TF_SHARED_PROBE`). Raw: raw/fix3c/,
scripts probe.sh and order.sh.

| Setting (fresh server, prose 4 / 2 / 8, then code) | Prose 4 | Prose 2 | Prose 8 | Code 4 / 8 / 16 |
|---|---:|---:|---:|---|
| 0015 as committed | 75.5 | 45.8 | 113.7 | 155.0 / 200.1 / 228.0 |
| 0015 + probe | 75.2 | 46.8 | 111.4 | 154.2 / 197.4 / 230.4 |
| pre-0015 pricing (`TF_HOLD_SHARED=0`) | 74.7 | 48.4 | 99.5 | 156.7 / 205.1 / 219.6 |
| 0015, benchmark order (code 1-16, then prose 1, 2, 4, 4, 4) | 74.5 / 74.9 / 72.8 | 45.8 | - | 154.8 / 200.1 / 226.5 |

Budget log, 0015 at 4 streams: 6,191 of 6,340 stream-rounds drafted (97.7%); first-draft chances ranged 0.40-0.80 and moved
round to round; no stream stuck plain. The probe changes nothing measurable. 0015 holds no 4-stream regression: six runs in
both orders gave 72.8-75.5 (Phase 3's two runs: 73.3, 76.4); the 65.8 is an outlier (each figure is already a median of three;
prose at T 0.7 writes different text every run). The probe is not kept.

## Final two-Spark measurements: the recipe build (patches 0001-0015, tree de18a25b)

Recipe `ripple-2x`, pair-pny, built by its own zig_prepare.sh. Raw: raw/final-2x/ (run2x.sh, p4-2x.sh). Part A by the recipe's
start.sh (Phase 2's configs); prefill on the production launcher (1 x 1M); decode on a temporary 4 x 256K launcher (removed).

Goldens vs Phase 2 (`phase2/recipe-*.json`): plain, drafted and four streams each 3 of 4 identical, coding differs (pfdense).
All four plain replies byte-identical to the four-Spark Phase 4 build's: two and four Sparks still agree.

| One stream, decode_bench (tok/s) | Phase 1 (reference pack) | Phase 4 |
|---|---:|---:|
| coding / tool call / chat, plain | 10.2 / 10.9 / 10.0 | 10.5 / 10.89 / 9.92 |
| coding / tool call / chat, DFlash2 | 36.1 / 31.6 / 15.8 | 36.28 / 31.66 / 15.79 |

1M retrieval: 5,438 s (1 h 31 min), 186.7 tok/s (Phase 1: 6,484 s, 156.6), correct; decode after it 6.52 tok/s (5.22).

| SparkMan prefill | 4K | 8K | 16K | 32K | 64K | 128K |
|---|---:|---:|---:|---:|---:|---:|
| 2x baseline | 415 | 413 | 408 | 399 | 378 | 344 |
| recipe build | 634 | 634 | 632 | 611 | 573 | 503 |

The reduce-scatter (0011) does not apply below three ranks; the gain (+46 to 55%) is pfdense and the overlap.

| Streams (4 x 256K) | Code | Prose |
|---:|---:|---:|
| 1 | 45.3 | 16.0 |
| 2 | 71.9 | 30.1 |
| 4 | 109.9 | 51.5 |

No two-Spark multi-stream baseline was measured before Phase 4.
