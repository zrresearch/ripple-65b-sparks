# pfdense (TensorFold's fused trellis-decoding prefill GEMM, k10) on the same rank slices, against ExLlamaV3's output
import torch, time, json, ctypes
from safetensors import safe_open
from exllamav3.modules.quant.exl3 import LinearEXL3
from exllamav3.ext import exllamav3_ext as ext
lib=ctypes.CDLL("/b/libpfd10.so"); f=lib.pfd10
f.argtypes=[ctypes.c_void_p]*2+[ctypes.c_longlong]*2+[ctypes.c_void_p]*2+[ctypes.c_int]*6
D="/m"; L=1; W=4
idx=json.load(open(D+"/model.safetensors.index.json"))["weight_map"]
def T(name):
    with safe_open(D+"/"+idx[name], "pt", device="cuda") as fh: return fh.get_tensor(name)
cut={"q_proj":"n","k_proj":"n","v_proj":"n","g_proj":"n","o_proj":"k","gate_proj":"n","up_proj":"n","down_proj":"k"}
lins={}
for p,how in cut.items():
    pre=f"model.layers.{L}.{"mlp" if p in ("gate_proj","up_proj","down_proj") else "self_attn"}.{p}"
    tr,suh,svh,m1=T(pre+".trellis"),T(pre+".suh"),T(pre+".svh"),T(pre+".mul1")
    K,N=tr.shape[0]*16,tr.shape[1]*16
    if how=="n": n=N//W; tr=tr[:, :n//16].contiguous(); svh=svh[:n].contiguous(); N=n
    else: k=K//W; tr=tr[:k//16].contiguous(); suh=suh[:k].contiguous(); K=k
    lins[p]=(LinearEXL3(None,K,N,suh=suh,svh=svh,trellis=tr,mul1=m1),K,N)
def tm(fn,reps=5):
    fn(); torch.cuda.synchronize(); t=time.perf_counter()
    for _ in range(reps): fn()
    torch.cuda.synchronize(); return (time.perf_counter()-t)/reps
for M in (128,512,1024,2048,4096):
    best={}
    for cfg in range(8):
        tot=0; err=0; ok=True
        for p,(l,K,N) in lins.items():
            x=torch.randn(M,K,dtype=torch.half,device="cuda")*0.5
            xh=torch.empty_like(x); y=torch.empty(M,N,dtype=torch.half,device="cuda")
            tw=40; sk=(N//16)*tw; snb=8*tw
            def run():
                ext.had_r_128(x,xh,l.suh,None,1.0)
                if f(xh.data_ptr(),l.trellis.data_ptr(),sk,snb,l.svh.data_ptr(),y.data_ptr(),M,K,N,0,cfg,8): raise RuntimeError("cfg")
            try: tot+=tm(run)
            except RuntimeError: ok=False; break
            ref=torch.cat([l.forward(x[r:r+128].contiguous(),{"reconstruct":False}) for r in range(0,M,128)]).float()
            err=max(err,((y.float()-ref).norm()/ref.norm()).item())
        if ok: best[cfg]=(tot,err)
    fl=2*M*sum(k*n for (l,k,n) in lins.values())
    c=min(best,key=lambda c:best[c][0]); t,e=best[c]
    print(f"M={M:5d}: pfdense best cfg {c}: {t*1e3:6.1f} ms ({fl/t/1e12:5.1f} TFLOPS, incl. rot_in)  rel diff vs exllamav3 {e:.1e}   all cfgs ms: "+" ".join(f"{k}:{v[0]*1e3:.1f}" for k,v in sorted(best.items())), flush=True)
