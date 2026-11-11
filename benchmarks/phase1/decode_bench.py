#!/usr/bin/env python3
"""Single-stream decode speed, the recipe's way: greedy, 512-token replies, three kinds of prompt.

  decode_bench.py <base url> <model> [--max 512] [--runs 2] [--out file.json]

Streams each reply and times decode from the first generated token to the last
(prompt reading excluded). Token counts come from the server's usage block.
"""
import json, sys, time, urllib.request

PROMPTS = {
    "coding": "Write a Python function that parses an ISO 8601 duration string such as P3DT4H12M5S into a "
              "datetime.timedelta. Handle years and months by raising ValueError. Include type hints, a docstring "
              "and five doctest examples.",
    "agent tool call": "You are an agent with a tool `run(cmd: str)` that executes a shell command and returns its "
                       "output. Respond only with tool calls, as JSON objects one per line, of the form "
                       "{\"tool\": \"run\", \"cmd\": \"...\"}. Task: find the five largest files under /var/log, show "
                       "their sizes, then compress any older than seven days into /tmp/archive with gzip, keeping "
                       "the originals.",
    "chat": "My partner and I are planning a four-day autumn trip to Glacier National Park. We like moderate hikes, "
            "quiet mornings and good food. What would a sensible day-by-day plan look like, and what should we "
            "watch out for with weather and road closures?",
}


def one(base, model, prompt, max_tokens):
    body = json.dumps({"model": model, "messages": [{"role": "user", "content": prompt}], "max_tokens": max_tokens,
                       "temperature": 0, "stream": True, "stream_options": {"include_usage": True}}).encode()
    req = urllib.request.Request(base + "/v1/chat/completions", body, {"content-type": "application/json"})
    t0 = time.time(); first = last = None; usage = None; chunks = 0
    with urllib.request.urlopen(req, timeout=3600) as r:
        for line in r:
            line = line.strip()
            if not line.startswith(b"data:") or line == b"data: [DONE]":
                continue
            d = json.loads(line[5:])
            if d.get("usage"):
                usage = d["usage"]
            for c in d.get("choices") or []:
                delta = c.get("delta") or {}
                if delta.get("content") or delta.get("reasoning_content") or delta.get("reasoning"):
                    now = time.time(); first = first or now; last = now; chunks += 1
    n = (usage or {}).get("completion_tokens") or chunks
    dec = (n - 1) / (last - first) if first and last and last > first else None
    return {"completion_tokens": n, "first_token_s": round(first - t0, 2) if first else None,
            "decode_tok_s": round(dec, 2) if dec else None, "chunks": chunks}


if __name__ == "__main__":
    a = sys.argv[1:]
    base, model = a[0].rstrip("/"), a[1]
    mx = int(a[a.index("--max") + 1]) if "--max" in a else 512
    runs = int(a[a.index("--runs") + 1]) if "--runs" in a else 2
    out = {}
    one(base, model, "Say hello.", 16)  # warm
    for k, p in PROMPTS.items():
        rs = [one(base, model, p, mx) for _ in range(runs)]
        out[k] = {"runs": rs, "decode_tok_s": round(sum(r["decode_tok_s"] for r in rs) / len(rs), 2)}
        print(k, out[k]["decode_tok_s"], "tok/s", [r["completion_tokens"] for r in rs], flush=True)
    if "--out" in a:
        json.dump(out, open(a[a.index("--out") + 1], "w"), indent=1)
