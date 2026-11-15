import json,time,urllib.request,uuid,random,sys
random.seed(1); words="the of and to in a is that for it as was with be by on not he this are or his from at which but have an they you were".split()
filler=" ".join(random.choice(words) for _ in range(int(sys.argv[1]) if len(sys.argv)>1 else 7600))
out=[]
for rep in range(2):
    p=f"[pf {uuid.uuid4()}]\nIgnore the filler below. Reply with the single word OK.\n{filler}\nReply OK."
    b={"model":"Ripple-65B-Preview","messages":[{"role":"user","content":p}],"max_tokens":1,"temperature":0}
    t=time.time(); r=json.load(urllib.request.urlopen(urllib.request.Request("http://<addr>:8888/v1/chat/completions",json.dumps(b).encode(),{"Content-Type":"application/json"}),timeout=1800))
    out.append(r["usage"]["prompt_tokens"]/(time.time()-t))
print("%d tokens: %s tok/s" % (r["usage"]["prompt_tokens"], " / ".join("%.0f"%x for x in out)))
