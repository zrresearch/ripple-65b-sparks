# Microbenchmark on GB10: one Ripple layer, a TP=4 rank's slices, EXL3 trellis kernel (128-row blocks, as TensorFold)
# vs decode-to-fp16 + dense GEMM (ExLlamaV3's reconstruct_hgemm, plain and fused), at several chunk sizes.
import torch, time, json
from safetensors import safe_open
from exllamav3.modules.quant.exl3 import LinearEXL3
D="/m"; L=1; W=4
idx=json.load(open(D+"/model.safetensors.index.json"))["weight_map"]
def T(name):
    with safe_open(D+"/"+idx[name], "pt", device="cuda") as f: return f.get_tensor(name)
cut={"q_proj":"n","k_proj":"n","v_proj":"n","g_proj":"n","o_proj":"k","gate_proj":"n","up_proj":"n","down_proj":"k"}
lins={}
for p,how in cut.items():
    pre=f"model.layers.{L}.{"self_attn" if p[0] in "qkvgo" and p not in ("gate_proj",) else "mlp"}.{p}"
    tr,suh,svh,m1=T(pre+".trellis"),T(pre+".suh"),T(pre+".svh"),T(pre+".mul1")
    K,N=tr.shape[0]*16,tr.shape[1]*16
    if how=="n": n=N//W; tr=tr[:, :n//16].contiguous(); svh=svh[:n].contiguous(); N=n
    else: k=K//W; tr=tr[:k//16].contiguous(); suh=suh[:k].contiguous(); K=k
    lins[p]=(LinearEXL3(None,K,N,suh=suh,svh=svh,trellis=tr,mul1=m1),K,N)
def tm(f,reps=5):
    f(); torch.cuda.synchronize(); t=time.perf_counter()
    for _ in range(reps): f()
    torch.cuda.synchronize(); return (time.perf_counter()-t)/reps
print("per-rank shapes:", {p:(k,n) for p,(l,k,n) in lins.items()})
for M in (128,512,1024,2048):
    tt=tr_=tf=0; err=0
    for p,(l,K,N) in lins.items():
        x=torch.randn(M,K,dtype=torch.half,device="cuda")*0.5
        def trellis():
            return torch.cat([l.forward(x[r:r+128].contiguous(),{"reconstruct":False}) for r in range(0,M,128)])
        def recon(): return l.forward(x,{"reconstruct":True})
        tt+=tm(trellis); tr_+=tm(recon)
        a,b=trellis().float(),recon().float(); err=max(err,((a-b).norm()/a.norm()).item())
    fl=2*M*sum(k*n for (l,k,n) in lins.values())
    print(f"M={M:5d}: trellis {tt*1e3:7.1f} ms ({fl/tt/1e12:5.1f} TFLOPS)  reconstruct+gemm {tr_*1e3:7.1f} ms ({fl/tr_/1e12:5.1f} TFLOPS)  x{tt/tr_:.2f}  max rel diff {err:.1e}", flush=True)
