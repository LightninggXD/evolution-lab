"""Write tools/_disk_hashes.json -- every src/ script's byte length and rolling hash.

Half of the hash sweep. The other half runs inside Studio: it GETs this file over the local
bridge (tools/recv_server.py) and returns only the lines that differ, so a full 200-file sweep
costs one small MCP result instead of the whole census twice.
"""

import json
import os

SUFFIX = [(".server.lua", "Script"), (".client.lua", "LocalScript"), (".lua", "ModuleScript")]


def roll(b):
    h = 0
    for x in b:
        h = (h * 31 + x) % 2147483647
    return h


def main():
    out = {}
    for root, _dirs, files in os.walk("src"):
        for name in files:
            cls = None
            for suf, c in SUFFIX:
                if name.endswith(suf):
                    cls, sl = c, len(suf)
                    break
            if not cls:
                continue
            path = os.path.join(root, name)
            with open(path, "rb") as fh:
                data = fh.read()
            dotted = os.path.relpath(path, "src").replace(os.sep, ".")[:-sl]
            out[dotted] = [len(data), roll(data), cls]
    tmp = "tools/_disk_hashes.json.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(out, fh)
    os.replace(tmp, "tools/_disk_hashes.json")
    print(f"{len(out)} files hashed")


if __name__ == "__main__":
    main()
