import json, sys
from datasets import load_dataset
from tokenizers import Tokenizer
tok = Tokenizer.from_file(sys.argv[1]); target = int(sys.argv[2])
text = "\n\n".join(t for t in load_dataset("Salesforce/wikitext", "wikitext-2-raw-v1", split="train")["text"] if t.strip())
ids = tok.encode(text).ids
print("source tokens", len(ids), file=sys.stderr)
reps = []
while sum(map(len, reps)) < target: reps.append(ids)
ids = sum(reps, [])[:target]
needle = " The access code for the Larchmont archive is 7319-KESTREL-0442. "
cut = int(len(ids) * 0.6)
body = tok.decode(ids[:cut]) + needle + tok.decode(ids[cut:])
q = "\n\nAbove is a long collection of encyclopedia articles. Somewhere in it is one sentence giving the access code for the Larchmont archive. What is that access code? Reply with the code only."
msg = [{"role": "user", "content": body + q}]
json.dump({"messages": msg}, open(sys.argv[3], "w"))
print("prompt tokens approx", len(tok.encode(body + q).ids), file=sys.stderr)
