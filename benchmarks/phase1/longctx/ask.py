import json, sys, time, urllib.request
p = json.load(open(sys.argv[1])); out = sys.argv[2]
body = json.dumps({"model": "Ripple-65B-Preview", "messages": p["messages"], "max_tokens": 4096, "temperature": 0,
                   "stream": True, "stream_options": {"include_usage": True}}).encode()
req = urllib.request.Request("http://127.0.0.1:8888/v1/chat/completions", body, {"content-type": "application/json"})
t0 = time.time(); first = last = None; usage = None; text = ""; reasoning = ""
with urllib.request.urlopen(req, timeout=4 * 3600) as r:
    for line in r:
        line = line.strip()
        if not line.startswith(b"data:") or line == b"data: [DONE]": continue
        d = json.loads(line[5:]); usage = d.get("usage") or usage
        for c in d.get("choices") or []:
            dl = c.get("delta") or {}
            piece = dl.get("content") or ""; rp = dl.get("reasoning_content") or dl.get("reasoning") or ""
            if piece or rp:
                now = time.time(); first = first or now; last = now; text += piece; reasoning += rp
n = (usage or {}).get("completion_tokens"); pt = (usage or {}).get("prompt_tokens")
res = {"prompt_tokens": pt, "first_token_s": round(first - t0, 1), "prompt_tok_s": round(pt / (first - t0), 1) if pt else None,
       "completion_tokens": n, "decode_tok_s": round((n - 1) / (last - first), 2) if n and last > first else None,
       "answer": text.strip()[-300:], "reasoning_tail": reasoning[-500:], "found": "7319-KESTREL-0442" in text, "usage": usage}
json.dump(res, open(out, "w"), indent=1); print(json.dumps({k: res[k] for k in ("prompt_tokens","first_token_s","prompt_tok_s","completion_tokens","decode_tok_s","found","answer")}))
