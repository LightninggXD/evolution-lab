#!/usr/bin/env python3
"""Reachability lint for the RemoteEvents/RemoteFunctions in src/.

The other three tools all ask questions about ONE file. `luastruct.py` proves its blocks balance,
`luanames.py` proves a name exists somewhere in it, `luascope.py` proves a name is visible where it
is read. All three were clean over the whole repo on the day this was written, and the trading
feature was still completely unreachable -- because the defect was not inside any file:

    -- TradeService.lua (server), since 8.6
    local reqRemote = ensureRemote("TradeRequest")
    reqRemote.OnServerEvent:Connect(function(player, targetUserId) ... end)

    -- MainUI.client.lua
    (nothing. no button in the game ever fired TradeRequest.)

Every name in both halves is in scope and correct. Luau compiles it. It is a conversation with one
speaker, and the only way to see it is to look at BOTH SIDES AT ONCE -- which is this tool.

    python tools/luaremotes.py            # check every .lua under src/
    python tools/luaremotes.py --verbose  # ...and print the full map, remote by remote

Exit code 0 when every remote has both a speaker and a listener on the pair of sides it needs,
1 otherwise.

IT REPRODUCES 15.11 AND IT FOUND 15.12 ON THE SAME RUN, which are the two directions of one shape:

    TradeRequest -- the server listens for it and NO CLIENT EVER FIRES IT   (a feature with no door)
    CollectClick -- the server listens for it and NO CLIENT EVER FIRES IT   (a faucet only a cheat
                                                                            client can reach)

Both read identically here, and that is the point: the tool reports the fact, and which of the two
it is depends on whether the remote pays out. Run against the commit before 15.11's fix, it prints
`TradeRequest`; run against the fix, it does not.

THE SECOND CHECK IS A WARNING, NOT A FAILURE, and it is 15.9's shape rather than 15.11's:
a one-shot `X.OnClientEvent:Connect` where `X` came from a `FindFirstChild`. That lookup does not
wait, so if the server creates the remote lazily -- and several services here create theirs at the
moment of first use -- the connect is skipped without a word and that client can never receive the
remote again for the whole session. `WaitForChild` blocks and a bare `Remotes.NAME` errors loudly;
this is the only form that fails in silence. It cannot be an error, because whether it is fatal
depends on the server's creation order, which is not in the file.

HOW IT DECIDES WHICH SIDE A CALL IS ON. Not from the file's path -- from the API, which is not
ambiguous: `FireServer` / `InvokeServer` / `OnClientEvent` / `OnClientInvoke` only exist on a
client, and `FireClient` / `FireAllClients` / `OnServerEvent` / `OnServerInvoke` only exist on a
server. A shared ModuleScript in ReplicatedStorage runs on whichever side required it, and this is
why that never has to be worked out.

HOW IT RESOLVES A NAME. Four forms, which is all this codebase uses:
    Remotes.NAME:FireServer(...)                     -- direct
    Remotes:FindFirstChild("NAME").OnServerEvent     -- direct, through a lookup
    local r = ensureRemote("NAME") ... r:FireServer  -- through one local
    remote():FireAllClients(...)                     -- through one find-or-create helper
The third resolves against the NEAREST PRECEDING binding of that local's name rather than a
whole-file map: `MainUI` binds a local called `remote` to eleven different remotes and `rem` to six
more, and keeping the first made six live features look unreachable on the first run.

WHAT IT DELIBERATELY DOES NOT DO. It does not follow a remote through a table, a function argument,
a helper that returns more than one remote, or a name built at run time (`Remotes[kind .. "Reward"]`).
It DOES resolve multi-line local assignments in the same file (like `cond and A or B`), proving 
a use of `<local>:FireServer(` fires all names bound to that local.
Anything it cannot resolve is dropped rather than guessed at, so a clean run is not a proof of
reachability -- it is the absence of the one shape it does prove.

THE BASELINE (2026-08-15), so a run can be read at a glance:
  * **0 findings.** `CollectClick` was the only one and it is fixed (15.12).
  * **3 warnings**, all currently safe and all worth keeping visible: `TradeUpdate` and
    `TradeInvite` (`MainUI`) are eagerly created by `TradeService.Init` since 15.9, and
    `OpenGroupRewards` by `RewardService.Init`. Every one of the three would become 15.9 again the
    day somebody moves that `ensureRemote` call out of an `Init`.
  * archived copies (`*_pre_*`, `*_removed_*`) are skipped outright -- dead files, live-looking
    remotes.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"

# The API is the side. This is the whole classification.
CLIENT_SENDS = {"FireServer", "InvokeServer"}
CLIENT_LISTENS = {"OnClientEvent", "OnClientInvoke"}
SERVER_SENDS = {"FireClient", "FireAllClients"}
SERVER_LISTENS = {"OnServerEvent", "OnServerInvoke"}
ALL_API = CLIENT_SENDS | CLIENT_LISTENS | SERVER_SENDS | SERVER_LISTENS

NAME = r"[A-Za-z_][A-Za-z0-9_]*"

# The folder every remote hangs off. It is fetched by the same `WaitForChild("Remotes")` call the
# remotes themselves are, so without this it resolves as a remote named "Remotes" that nothing
# sends -- the tool's own first false positive.
FOLDER = "Remotes"

# `local r = Remotes:FindFirstChild("X") ; if not r then r = Instance.new("RemoteEvent") ... end`
# is how half the services create a remote on demand. The second line is a binding too, and taking
# its string bound the local to a CLASS name -- which then swallowed four real pairings under one
# invented remote called "RemoteEvent". A class is never a remote's name.
CLASS_NAMES = {"RemoteEvent", "RemoteFunction", "BindableEvent", "BindableFunction", "Folder"}

# `x = <rhs>` or `local x = <rhs>`. Plain assignment counts too: several clients forward-declare
# the local and fill it in a `task.spawn`, which is exactly where a slow remote is waited for.
BIND = re.compile(r"^[ \t]*(?:local[ \t]+)?(%s)[ \t]*=([^\n]*(?:\n[ \t]+(?:and|or)[ \t]+[^\n]*)*)" % NAME, re.M)
# every `("Name")` inside the right-hand side, with any trailing arguments -- `WaitForChild` takes
# a timeout, and requiring a bare `)` after the string is what hid AutoAttack and CombatFx
IN_CALL = re.compile(r"\([ \t]*[\"'](%s)[\"'][ \t]*(?:,[^)]*)?\)" % NAME)
RHS_DOT = re.compile(r"\b%s\.(%s)\b" % (FOLDER, NAME))
# `Remotes.NAME:FireServer(` / `Remotes.NAME.OnServerEvent`
USE_DOT = re.compile(r"\b%s\.(%s)[ \t]*[:.](%s)\b" % (FOLDER, NAME, NAME))
# `Remotes:FindFirstChild("NAME"):FireServer(` and the WaitForChild-with-timeout form
USE_LOOKUP = re.compile(r"\([ \t]*[\"'](%s)[\"'][ \t]*(?:,[^)]*)?\)[ \t]*[:.](%s)\b" % (NAME, NAME))
# `r:FireServer(` / `r.OnServerEvent`
USE_VAR = re.compile(r"\b(%s)[ \t]*[:.](%s)\b" % (NAME, NAME))

# ONE HELPER DEEP, AND NO FURTHER. `AnnounceService` sends through `remote():FireAllClients(...)`,
# where `remote()` is a top-level local function that finds-or-creates the remote and returns it --
# the tool's second false positive, and a shape common enough here to be worth resolving. A
# top-level `local function` ends at an `end` in column 0, so the body is bounded exactly; if
# exactly ONE remote name is bound inside it, the function IS that remote. More than one and it is
# left unresolved, because then the return value depends on an argument.
HELPER = re.compile(r"^local function (%s)\([^\n]*\)\n(.*?)^end$" % NAME, re.M | re.S)
USE_CALL = re.compile(r"\b(%s)\(\)[ \t]*[:.](%s)\b" % (NAME, NAME))


def strip_comments(src):
    """Blank out comments, keeping line breaks and string literals intact."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c in "\"'":
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == "\\" else 1
            out.append(src[i:j + 1])
            i = j + 1
            continue
        if src.startswith("[[", i) or re.match(r"\[=+\[", src[i:i + 8] or ""):
            m = re.match(r"\[(=*)\[", src[i:])
            close = "]" + m.group(1) + "]"
            j = src.find(close, i + m.end())
            j = n if j == -1 else j + len(close)
            out.append(src[i:j])
            i = j
            continue
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, i + m.end())
                j = n if j == -1 else j + len(close)
                out.append(re.sub(r"[^\n]", " ", src[i:j]))
                i = j
                continue
            j = src.find("\n", i)
            j = n if j == -1 else j
            out.append(" " * (j - i))
            i = j
            continue
        out.append(c)
        i += 1
    return "".join(out)


def scan(path, sightings, silent):
    src = strip_comments(path.read_text(encoding="utf-8"))
    try:
        rel = path.relative_to(ROOT).as_posix()
    except ValueError:
        rel = path.as_posix()

    # THE LAST NAME IN THE CHAIN IS THE REMOTE. `RS:WaitForChild("Remotes"):WaitForChild("AutoAttack", 30)`
    # names two children and only the second one is a remote; taking the first bound every such
    # local to the folder instead.
    #
    # AND A BINDING IS A POSITION, NOT A NAME. `MainUI` alone binds a local called `remote` to
    # eleven different remotes, and `rem` to six more -- keeping the first and skipping the rest
    # made six live features look unreachable on this tool's first run. A use resolves against the
    # NEAREST PRECEDING binding of that name, which is not Lua's scoping but is wrong only in the
    # direction that loses findings: a use inside a function whose binding sits below it resolves
    # to the wrong remote or to none, never to a fabricated pairing.
    binds = []
    for m in BIND.finditer(src):
        rhs = m.group(2)
        found = [g for g in IN_CALL.findall(rhs) if g != FOLDER and g not in CLASS_NAMES]
        if not found:
            found = RHS_DOT.findall(rhs)
        if found:
            binds.append((m.start(1), m.group(1), found, "find" if "FindFirstChild" in rhs else "wait"))

    def resolve(var, pos):
        best = (None, None)
        for at, name, remotes, how in binds:
            if at < pos and name == var:
                best = (remotes, how)
            elif at >= pos:
                break
        return best

    def record(remote, api, pos):
        if remote == FOLDER:
            return
        line = src.count("\n", 0, pos) + 1
        sightings.setdefault(remote, {k: [] for k in ALL_API})[api].append(f"{rel}:{line}")

    helper2remote = {}
    for m in HELPER.finditer(src):
        names = {g for g in IN_CALL.findall(m.group(2))
                 if g != FOLDER and g not in CLASS_NAMES}
        names |= set(RHS_DOT.findall(m.group(2)))
        if len(names) == 1:
            helper2remote[m.group(1)] = names.pop()

    # the two forms that name the remote at the call site itself -- no binding needed
    seen = set()
    for m in USE_CALL.finditer(src):
        if m.group(2) in ALL_API and m.group(1) in helper2remote:
            record(helper2remote[m.group(1)], m.group(2), m.start())
            seen.add(m.start(2))
    for m in USE_DOT.finditer(src):
        if m.group(2) in ALL_API:
            record(m.group(1), m.group(2), m.start())
            seen.add(m.start(2))
    for m in USE_LOOKUP.finditer(src):
        if m.group(2) in ALL_API:
            record(m.group(1), m.group(2), m.start())
            seen.add(m.start(2))
            if m.group(2) in CLIENT_LISTENS and "FindFirstChild" in src[max(0, m.start() - 40):m.start()]:
                silent.append((m.group(1), f"{rel}:{src.count(chr(10), 0, m.start()) + 1}"))

    for m in USE_VAR.finditer(src):
        if m.group(2) not in ALL_API or m.start(2) in seen:
            continue
        remotes, how = resolve(m.group(1), m.start(1))
        if not remotes:
            continue
        for remote in remotes:
            record(remote, m.group(2), m.start())
            # 15.9's shape: a ONE-SHOT connect on a lookup that can return nil. `FindFirstChild` does
            # not wait, so if the remote is created later -- and half the services here create theirs
            # on demand, at the moment of first use -- the connect is skipped without a word and the
            # client can never receive that remote for the rest of the session. `WaitForChild` blocks
            # and a bare `Remotes.NAME` errors loudly; only this form fails in silence.
            if m.group(2) in CLIENT_LISTENS and how == "find":
                silent.append((remote, f"{rel}:{src.count(chr(10), 0, m.start()) + 1}"))


def main(argv):
    verbose = "--verbose" in argv
    custom_src = Path(argv[0]) if argv and not argv[0].startswith("--") else SRC
    files = sorted(p for p in custom_src.rglob("*.lua")
                   if "_pre_" not in p.name and "_removed_" not in p.name)

    sightings, silent = {}, []
    for p in files:
        scan(p, sightings, silent)

    findings = []
    for remote in sorted(sightings):
        s = sightings[remote]
        c_send = [x for k in CLIENT_SENDS for x in s[k]]
        c_recv = [x for k in CLIENT_LISTENS for x in s[k]]
        s_send = [x for k in SERVER_SENDS for x in s[k]]
        s_recv = [x for k in SERVER_LISTENS for x in s[k]]

        if s_recv and not c_send:
            findings.append((remote, "the server listens for it and NO CLIENT EVER FIRES IT", s_recv))
        if c_send and not s_recv:
            findings.append((remote, "a client fires it and NO SERVER LISTENS", c_send))
        if c_recv and not s_send:
            findings.append((remote, "a client listens for it and NO SERVER EVER SENDS IT", c_recv))
        if s_send and not c_recv:
            findings.append((remote, "the server sends it and NO CLIENT LISTENS", s_send))

        if verbose:
            print(f"{remote}")
            for label, hits in (("client fires ", c_send), ("server listens", s_recv),
                                ("server sends ", s_send), ("client listens", c_recv)):
                print(f"    {label}: {', '.join(hits) if hits else '-'}")

    if findings:
        print(f"BAD {len(findings)} unreachable remote(s) of {len(sightings)} resolved:\n")
        for remote, why, hits in findings:
            print(f"  {remote} -- {why}")
            for h in hits[:6]:
                print(f"      {h}")
    else:
        print(f"OK  {len(sightings)} remotes resolved across {len(files)} files; "
              "every one has a speaker and a listener")

    # THE SECOND CHECK, and it is a warning rather than a failure: a nil lookup here is only fatal
    # when the server creates the remote lazily, which this tool cannot see. It is printed every
    # run because 15.9 shipped exactly once and cost a whole feature.
    if silent:
        print(f"\n!   {len(silent)} one-shot client connect(s) on a FindFirstChild lookup "
              "-- nil here is silent, and the client never receives that remote again:")
        for remote, where in sorted(set(silent)):
            print(f"      {remote:<22} {where}")

    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
