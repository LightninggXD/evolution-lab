"""Trace a Studio-side rolling hash back to the commit its file came from.

Usage: provenance.py <hash> <path> [<hash> <path> ...]

A hit means Studio's copy IS some past commit verbatim -- it holds no
uncommitted work, so pushing src/ over it is a pure fast-forward. A miss is
the alarm: that file has Studio-only content.
"""
import subprocess
import sys


def roll(b):
    h = 0
    for c in b:
        h = (h * 31 + c) % 2147483647
    return h


def revs(path):
    out = subprocess.run(["git", "log", "--format=%h %ad", "--date=short", "--", path],
                         capture_output=True, text=True).stdout
    return [line.split(" ", 1) for line in out.splitlines() if line.strip()]


args = sys.argv[1:]
for i in range(0, len(args), 2):
    want, path = int(args[i]), args[i + 1]
    hit = None
    rl = revs(path)
    for rev, date in rl:
        blob = subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True).stdout
        if roll(blob) == want:
            hit = (rev, date)
            break
    print(f"{path}: {'HIT ' + hit[0] + ' (' + hit[1] + ')' if hit else 'NO MATCH IN ' + str(len(rl)) + ' REVISIONS'}")
