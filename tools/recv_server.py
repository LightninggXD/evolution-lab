"""Receive Source text POSTed out of Roblox Studio and write it to disk.

The HTTP bridge (tools/studio_mcp.py + `python -m http.server`) is one-way: Studio can GET
`src/` but a plain http.server refuses POST, which is why pulling Studio's work back to disk
used to mean hand-transcribing a diff. HttpService:PostAsync works fine -- it only ever needed
something on the other end that writes the body out.

Serves GET too, so this replaces http.server rather than running beside it.

POST /recv?path=<repo-relative path>   body = the file's exact Source
The path is confined to this repo; anything escaping it is refused.
"""

import http.server
import os
import sys
import urllib.parse

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/recv":
            self.send_error(404, "only /recv accepts a POST")
            return

        rel = urllib.parse.parse_qs(parsed.query).get("path", [""])[0]
        dest = os.path.abspath(os.path.join(ROOT, rel))
        if not rel or not dest.startswith(ROOT + os.sep):
            self.send_error(400, "path must stay inside the repo")
            return

        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        # newline="" so Studio's LF survives -- a CRLF here reads as a permanent size
        # difference on the next hash sweep.
        with open(dest, "wb") as fh:
            fh.write(body)

        h = 0
        for b in body:
            h = (h * 31 + b) % 2147483647
        print(f"{len(body):>8} bytes  hash {h:>10}  {rel}", flush=True)

        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(f"{len(body)} {h}".encode())

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8731
    http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
