# prose.py <base_url> <model>: Mia-style prose decode (T=0.7, thinking on) at 1/2/4/8 at once, median of 3
import json, sys, time, threading, urllib.request, statistics
URL, MODEL = sys.argv[1], sys.argv[2]
PROMPT = 'Write a long, flowing short story about a lighthouse keeper who discovers something unexpected washed up on the shore.'
def one(k, out):
    body = {'model': MODEL, 'messages': [{'role': 'user', 'content': f'{PROMPT} (variant {k})'}], 'max_tokens': 1024, 'temperature': 0.7,
            'stream': True, 'stream_options': {'include_usage': True}}
    req = urllib.request.Request(URL + '/chat/completions', json.dumps(body).encode(), {'Content-Type': 'application/json'})
    t0 = time.time(); first = None; toks = 0
    with urllib.request.urlopen(req, timeout=600) as r:
        for line in r:
            line = line.strip()
            if not line.startswith(b'data: ') or line == b'data: [DONE]': continue
            j = json.loads(line[6:])
            if j.get('usage'): toks = j['usage'].get('completion_tokens', toks)
            for c in j.get('choices', []):
                d = c.get('delta', {})
                if first is None and (d.get('content') or d.get('reasoning_content')): first = time.time()
    out.append((t0, first, time.time(), toks))
for c in [int(x) for x in (sys.argv[3] if len(sys.argv) > 3 else "1,2,4,8").split(",")]:
    runs = []
    for rep in range(3):
        out = []; th = [threading.Thread(target=one, args=(rep * 10 + k, out)) for k in range(c)]
        [t.start() for t in th]; [t.join() for t in th]
        b = min(o[1] for o in out); e = max(o[2] for o in out); n = sum(o[3] for o in out)
        per = statistics.mean(o[3] / (o[2] - o[1]) for o in out)
        runs.append((n / (e - b), per, statistics.median((o[1] - o[0]) * 1000 for o in out)))
    agg, per, ttft = (statistics.median(x[i] for x in runs) for i in range(3))
    print(f'{c} at once: {agg:6.1f} tok/s aggregate, {per:5.1f} per request, TTFT {ttft:4.0f} ms', flush=True)
