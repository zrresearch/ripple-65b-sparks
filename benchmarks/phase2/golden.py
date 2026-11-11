#!/usr/bin/env python3
"""Greedy replies to fixed prompts, saved whole, to show two builds produce the same bytes.

  golden.py <base url> <out.json> [--concurrent]     (record)
  golden.py --compare <a.json> <b.json>              (compare)

--concurrent sends the prompts together (one stream each) instead of one after another.
"""
import json, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor

LONG = " ".join(f"Record {i}: sensor {i % 17} read {((i * 7919) % 1000) / 10:.1f} degrees at minute {i}." for i in range(400))
PROMPTS = {
    "coding": "Write a Python function that parses an ISO 8601 duration string such as P3DT4H12M5S into a "
              "datetime.timedelta. Handle years and months by raising ValueError. Include type hints and a docstring.",
    "agent": "You have a tool run(cmd) that executes shell commands. Reply only with JSON tool calls, one per line. "
             "Task: list the five largest files under /var/log with their sizes.",
    "chat": "Suggest a sensible four-day autumn itinerary for Glacier National Park for two people who like moderate hikes.",
    "long": LONG + "\n\nWhich sensor had the highest reading at minute 397, and what was it? Then list the readings of sensor 3 "
            "between minutes 300 and 400.",
}


def ask(base, prompt):
    body = json.dumps({"model": "Ripple-65B-Preview", "messages": [{"role": "user", "content": prompt}],
                       "max_tokens": 384, "temperature": 0}).encode()
    req = urllib.request.Request(base + "/v1/chat/completions", body, {"content-type": "application/json"})
    r = json.load(urllib.request.urlopen(req, timeout=1800))
    m = r["choices"][0]["message"]
    return {"content": m.get("content"), "reasoning": m.get("reasoning_content") or m.get("reasoning"),
            "finish": r["choices"][0].get("finish_reason"), "usage": r.get("usage")}


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[0] == "--compare":
        x, y = json.load(open(a[1])), json.load(open(a[2]))
        same = True
        for k in x:
            ok = (x[k]["content"], x[k]["reasoning"]) == (y[k]["content"], y[k]["reasoning"])
            same &= ok
            print(f"{k}: {'identical' if ok else 'DIFFERS'} ({x[k]['usage']['completion_tokens']} / {y[k]['usage']['completion_tokens']} tokens)")
        sys.exit(0 if same else 1)
    base, out = a[0].rstrip("/"), a[1]
    if "--concurrent" in a:
        with ThreadPoolExecutor(len(PROMPTS)) as ex:
            res = dict(zip(PROMPTS, ex.map(lambda p: ask(base, p), PROMPTS.values())))
    else:
        res = {k: ask(base, p) for k, p in PROMPTS.items()}
    json.dump(res, open(out, "w"), indent=1)
    print({k: v["usage"]["completion_tokens"] for k, v in res.items()})
