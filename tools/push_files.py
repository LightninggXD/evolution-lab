"""Build the manifest for a src/ -> Studio push, and print the Luau pass that applies it.

    C:\\Python313\\python.exe tools/push_files.py --changed      (everything git reports under src/)
    C:\\Python313\\python.exe tools/push_files.py src/ServerScriptService/Telemetry.lua ...

This writes `tools/_push_manifest.json` and prints the Luau to paste into `execute_luau` (Edit
datamodel). Python cannot do the second half itself -- applying the sources means running code
inside Studio, which only the MCP tool can do -- so this deliberately stops at the boundary rather
than pretending to be a one-shot pusher.

WHY A MANIFEST RATHER THAN ONE CALL PER FILE. A phase-sized pass touches twenty-odd files, and
twenty MCP round trips can each fail halfway with no report of which ones landed. One pass reads
the manifest, fetches every file over the local HTTP bridge, writes it with `UpdateSourceAsync`
(the method that gets past the 200 KB write limit -- `CreatureService` is 208 KB) and then hashes
back what Studio actually holds. A partial write is a MISMATCH line, never a silent success.
Measured 2026-08-20: 24 files, all OK on the first run.

SERVE THE REPO FIRST, and serve it with `tools/recv_server.py` rather than `python -m http.server`:

    (C:/Python313/python.exe tools/recv_server.py 8731 >/dev/null 2>&1 &)

`http.server` answers 501 to a POST, and the same bridge is what pulls Studio's manifest back to
disk afterwards (see the sweep note in ROADMAP). Stop Play first -- writes need the Edit datamodel.

A script that does not exist yet is CREATED from the filename suffix:
    *.server.lua -> Script      *.client.lua -> LocalScript      *.lua -> ModuleScript
"""

import io
import json
import os
import subprocess
import sys

SUFFIX = [(".server.lua", "Script"), (".client.lua", "LocalScript"), (".lua", "ModuleScript")]
MANIFEST = "tools/_push_manifest.json"
PORT = 8731

LUA = '''
-- paste into execute_luau, datamodel_type = "Edit"
local Http = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
local BASE = "http://127.0.0.1:__PORT__"

local function roll(s)
\tlocal h, n, i = 0, #s, 1
\twhile i <= n do
\t\tlocal j = math.min(i + 2047, n)
\t\tlocal b = {string.byte(s, i, j)}
\t\tfor k = 1, #b do h = (h * 31 + b[k]) % 2147483647 end
\t\ti = j + 1
\tend
\treturn h
end

local manifest = Http:JSONDecode(Http:GetAsync(BASE .. "/__MANIFEST__"))
local report = {}
for _, item in ipairs(manifest) do
\tlocal okGet, src = pcall(function() return Http:GetAsync(BASE .. item.url) end)
\tif not okGet then
\t\ttable.insert(report, item.dotted .. " GET-FAIL " .. tostring(src))
\telse
\t\tlocal node, parts = game, {}
\t\tfor name in string.gmatch(item.dotted, "[^%.]+") do table.insert(parts, name) end
\t\tlocal failed = nil
\t\tfor idx, name in ipairs(parts) do
\t\t\tlocal nxt = node:FindFirstChild(name)
\t\t\tif not nxt then
\t\t\t\tif idx == #parts then
\t\t\t\t\tnxt = Instance.new(item.className)
\t\t\t\t\tnxt.Name = name
\t\t\t\t\tnxt.Parent = node
\t\t\t\telse
\t\t\t\t\tfailed = "MISSING-PARENT " .. name
\t\t\t\t\tbreak
\t\t\t\tend
\t\t\tend
\t\t\tnode = nxt
\t\tend
\t\tif failed then
\t\t\ttable.insert(report, item.dotted .. " " .. failed)
\t\telse
\t\t\tlocal okSet, err = pcall(function()
\t\t\t\tSES:UpdateSourceAsync(node, function() return src end)
\t\t\tend)
\t\t\tif not okSet then
\t\t\t\ttable.insert(report, item.dotted .. " SET-FAIL " .. tostring(err))
\t\t\telse
\t\t\t\tlocal live = node.Source
\t\t\t\tif #live == item.len and roll(live) == item.hash then
\t\t\t\t\ttable.insert(report, item.dotted .. " OK")
\t\t\t\telse
\t\t\t\t\ttable.insert(report, string.format("%s MISMATCH live=%d/%d want=%d/%d",
\t\t\t\t\t\titem.dotted, #live, roll(live), item.len, item.hash))
\t\t\t\tend
\t\t\tend
\t\tend
\tend
end
return table.concat(report, "\\n")
'''


def roll(data):
    h = 0
    for b in data:
        h = (h * 31 + b) % 2147483647
    return h


def dotted_of(rel):
    for suf, cls in SUFFIX:
        if rel.endswith(suf):
            return rel[len("src/"):-len(suf)].replace("/", "."), cls
    return None, None


def changed_files():
    out = subprocess.run(["git", "diff", "--name-only"], capture_output=True, text=True).stdout
    out += subprocess.run(["git", "ls-files", "-o", "--exclude-standard"],
                          capture_output=True, text=True).stdout
    seen, files = set(), []
    for line in out.splitlines():
        line = line.strip().replace("\\", "/")
        if line.startswith("src/") and line.endswith(".lua") and line not in seen:
            seen.add(line)
            files.append(line)
    return sorted(files)


def main(argv):
    files = changed_files() if (argv and argv[0] == "--changed") else \
        [a.replace("\\", "/") for a in argv]
    if not files:
        print("nothing to push", file=sys.stderr)
        return 1

    items = []
    for rel in files:
        dotted, cls = dotted_of(rel)
        if not dotted:
            print("SKIP (not a script): " + rel, file=sys.stderr)
            continue
        with io.open(rel, "rb") as fh:
            raw = fh.read()
        items.append({"url": "/" + rel, "dotted": dotted, "className": cls,
                      "len": len(raw), "hash": roll(raw)})
    items.sort(key=lambda x: x["dotted"])

    tmp = MANIFEST + ".tmp"
    with io.open(tmp, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(items))
    os.replace(tmp, MANIFEST)

    for i in items:
        print("  %-58s %d bytes" % (i["dotted"], i["len"]), file=sys.stderr)
    print("\n%d file(s) -> %s\n" % (len(items), MANIFEST), file=sys.stderr)
    print(LUA.replace("__PORT__", str(PORT)).replace("__MANIFEST__", MANIFEST))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
