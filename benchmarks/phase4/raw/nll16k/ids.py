# WikiText-2 test text as Ripple token ids: the first 16,384 (one long prompt, for tf-ricursive long)
import sys
from datasets import load_dataset
from tokenizers import Tokenizer
tok = Tokenizer.from_file(sys.argv[1])
text = "\n\n".join(t for t in load_dataset("Salesforce/wikitext", "wikitext-2-raw-v1", split="test")["text"] if t.strip())
ids = tok.encode(text).ids[:16384]
open(sys.argv[2], "w").write(",".join(map(str, ids)))
print(len(ids))
