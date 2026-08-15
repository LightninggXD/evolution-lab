"""Emit tools/manifest.json: every mirrored src/ script with its rolling hash.

The hash is the same one Studio computes (h = h*31 + byte, mod 2^31-1), so a
single Luau pass can compare both sides without transferring any source.
_PushBackup is excluded -- those are archived copies, not live scripts.
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")

def roll(b):
    h = 0
    for c in b:
        h = (h * 31 + c) % 2147483647
    return h

out = []
for dirpath, _dirnames, filenames in os.walk(SRC):
    for fn in sorted(filenames):
        if not fn.endswith(".lua"):
            continue
        full = os.path.join(dirpath, fn)
        rel = os.path.relpath(full, ROOT).replace("\\", "/")
        if "_PushBackup" in rel:
            continue
        data = open(full, "rb").read()
        out.append({
            "path": rel,
            "hash": roll(data),
            "bytes": len(data),
            "lines": data.count(b"\n") + 1,
        })

dest = os.path.join(ROOT, "tools", "manifest.json")
with open(dest, "w") as f:
    json.dump(out, f, indent=0)
print(len(out), "files ->", dest)
