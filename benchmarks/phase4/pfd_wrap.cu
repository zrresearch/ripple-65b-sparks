#include "exl3_block/pfdense.cuh"
#define DSV41_PFD_K2 10
#define DSV41_PFD_LN false
DSV41_PFD_CFGS(DSV41_PFD_INST)
extern "C" int pfd10(const void* xh, const void* T, long long sk, long long snb, const void* svh, void* out, int M, int K, int N,
                     int out_type, int cfg, int group) {
    dsv41_pfd::Args a{xh, (const uint32_t*)T, sk, snb, svh, nullptr, out, (long long)N, M, K, N, group, out_type};
    return dsv41_pfd::run<10, false>(a, cfg, 0) ? 0 : 1;
}
