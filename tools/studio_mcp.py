"""Talk to the Roblox Studio MCP proxy directly, over stdio, without an agent client.

WHY THIS EXISTS. The Studio bridge has two halves that fail separately and look identical from
inside an agent session -- "no Studio tools":

  * the PROXY (`mcp.bat` -> `StudioMCP.exe --stdio`) failing to start. A Studio update deletes the
    version folder the batch resolves, it exits 1 printing nothing, and the agent lists no tools.
    See the memory note `evolution-lab-mcp-stale-version`.
  * the PLUGIN inside Studio not being attached to a running proxy -- Studio open on the start page,
    the place not loaded, or the MCP server switched off in Assistant settings.

This script separates them in one command. `tools` speaks only to the proxy, so it answers even with
Studio shut; `exec` needs the whole chain. Proxy answers + exec says "Unable to reach Roblox Studio"
= the second half, and no amount of restarting the agent will fix it.

It is also a working escape hatch: when the agent's own MCP connection has dropped mid-session,
this reaches the live datamodel without restarting anything.

    python tools/studio_mcp.py tools                 # list the proxy's tools (proxy-only check)
    python tools/studio_mcp.py exec probe.lua        # run a Luau file, print what it returns
    python tools/studio_mcp.py <tool> args.json      # any other tool, arguments from a JSON file
"""

import json
import subprocess
import sys

MCP = r"C:\Users\Kristina\AppData\Local\Roblox\mcp.bat"


class Studio:
    def __init__(self):
        self.p = subprocess.Popen(
            ["cmd.exe", "/c", MCP],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, encoding="utf-8", errors="replace")
        self.n = 0
        self.req("initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "studio_mcp.py", "version": "1"},
        })
        # The proxy answers `initialize` but ignores everything after it until this notification
        # arrives -- a tools/call sent without it hangs forever with no error.
        self._write({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def _write(self, obj):
        self.p.stdin.write(json.dumps(obj) + "\n")
        self.p.stdin.flush()

    def req(self, method, params):
        self.n += 1
        rid = self.n
        self._write({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        # Interleaved notifications and log lines share this pipe, so read until the id matches
        # rather than taking the next line.
        while True:
            line = self.p.stdout.readline()
            if not line:
                return None
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if r.get("id") == rid:
                return r

    def call(self, name, args):
        return self.req("tools/call", {"name": name, "arguments": args})

    def close(self):
        self.p.kill()


def text_of(resp):
    if not resp:
        return "<no response>"
    if "error" in resp:
        return "ERROR: " + json.dumps(resp["error"])
    out = [c.get("text", json.dumps(c)) for c in resp.get("result", {}).get("content", [])]
    return "\n".join(out) if out else json.dumps(resp.get("result"))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    s = Studio()
    try:
        cmd = sys.argv[1]
        if cmd == "tools":
            r = s.req("tools/list", {})
            for t in r["result"]["tools"]:
                print(t["name"])
        elif cmd == "exec":
            with open(sys.argv[2], encoding="utf-8") as f:
                print(text_of(s.call("execute_luau", {"code": f.read()})))
        else:
            args = {}
            if len(sys.argv) > 2:
                with open(sys.argv[2], encoding="utf-8") as f:
                    args = json.load(f)
            print(text_of(s.call(cmd, args)))
    finally:
        s.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
