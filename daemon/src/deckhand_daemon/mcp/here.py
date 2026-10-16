"""Which session this server belongs to, and how it reaches the daemon.

**The session is found by walking up the process tree, not out of the environment.**
`CLAUDE_CODE_SESSION_ID` is put into the environment of the shells Claude Code spawns for its Bash
tool, and an MCP server is not one of those — it is started before any of that and does not get
it. What it does have is an ancestor: `claude` itself, whose pid keys
`~/.claude/sessions/<pid>.json`, which is the same join the whole of Deckhand hangs off. A walk
rather than one `getppid()` because the launch line goes through `uv`, so the parent is uv and
`claude` is its grandparent. The variable is still read first, free and correct where it is set.

**Inside OpenCode there is no such ancestor, and the call says who is asking instead.** One
`opencode serve` starts this server once per folder and shares it between every session there,
so neither the process tree nor the environment can name the session. OpenCode puts the calling
session's id into every tool call's `_meta` (`ai.opencode/sessionID`); `server.py` lifts it into
`calling` for the length of the call, and the record is asked of OpenCode's own service. A shell
OpenCode's agent runs carries `OPENCODE_SESSION_ID`, which is how the `deckhand` command finds the
same answer. The id is a correlation, not a credential, which is all it is used as here: it picks
whose folder a slip goes in, exactly as the Claude record does.

**The folder comes from that record too, never from `os.getcwd()`.** An MCP server inherits the
cwd of whatever started it, and a slip written in the wrong folder is invisible to the phone
rather than an error anybody sees.

**The daemon is reached over the loopback with the pairing token**, which is a file this process
can read because it runs as the person. Not by importing the daemon's own modules: the routes
carry the filter chain, the folder's refusals and the delivery record, and none of that is in the
functions underneath them.
"""

from __future__ import annotations

import json
import os
import subprocess
from contextvars import ContextVar

import httpx

from .. import config

# How far up to look for the `claude` that started this. Three would do — claude, uv, python —
# and the ceiling is only there so a strange tree ends the walk rather than the walk ending it.
ANCESTORS = 8
TIMEOUT = 20.0
#: Where OpenCode names the calling session in a tool call's `_meta`.
OPENCODE_META = "ai.opencode/sessionID"
#: The OpenCode session the tool call in flight was made for, or empty. Set by `server.py`.
calling: ContextVar[str] = ContextVar("calling", default="")


def _record(pid: int) -> dict | None:
    """The record `pid` wrote, in whichever config dir it was started under."""
    for home in config.claude_homes():
        try:
            held = json.loads((home / "sessions" / f"{pid}.json").read_text())
        except (OSError, json.JSONDecodeError):
            continue
        return held if isinstance(held, dict) and held.get("sessionId") else None
    return None


def _parent(pid: int) -> int | None:
    done = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)],
                          capture_output=True, text=True, check=False)
    parent = done.stdout.strip()
    return int(parent) if parent.isdigit() and int(parent) > 1 else None


def mine() -> dict | None:
    """This session's own record, or None when nothing above this process is a session.

    None is a real outcome, not a failure to handle later: run by hand from a terminal there is
    no session above, and every tool that needs one says so rather than guessing at the newest.
    """
    if asked := calling.get():
        return _opencode(asked)
    wanted = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    pid: int | None = os.getpid()
    for _ in range(ANCESTORS):
        pid = _parent(pid) if pid else None
        if pid is None:
            break
        if (held := _record(pid)) and (not wanted or held.get("sessionId") == wanted):
            return held
    if shell := os.environ.get("OPENCODE_SESSION_ID", ""):
        return _opencode(shell)
    return None


def _opencode(session_id: str) -> dict | None:
    """An OpenCode session's record, in the keys a Claude one has, asked of OpenCode's service.

    Imported here rather than at the top: only a call from OpenCode pays for the daemon's sessions
    package, and a Claude session's server never loads it.
    """
    from ..sessions import opencode

    found = opencode.fetch(session_id)
    if found is None:
        return None
    return {"sessionId": found["session_id"], "name": found["name"], "cwd": found["cwd"],
            "status": found["status"], "provider": found["provider"]}


def match(wanted: str, live: list[dict]) -> dict | None:
    """By id or name exactly, else by the one id it begins or the one name it is part of —
    `say utt` should not need the whole of `utt-review`. Two candidates is no match."""
    for exact in (s for s in live if wanted in (s.get("session_id"), s.get("name"))):
        return exact
    near = [s for s in live if (s.get("session_id") or "").startswith(wanted)
            or wanted.lower() in (s.get("name") or "").lower()]
    return near[0] if len(near) == 1 else None


def _said(answered: httpx.Response) -> str:
    """The daemon's own sentence: FastAPI's `detail`, not the JSON it is wrapped in."""
    try:
        body = answered.json()
    except ValueError:
        body = None
    said = body.get("detail") if isinstance(body, dict) else None
    return (str(said) if said else answered.text.strip())[:200]


async def reach(method: str, path: str, **sent: object) -> dict | list:
    """One call to the daemon. Every expected failure comes back as `{"error": sentence, "code":
    WORD}`, the code being what the `deckhand` command turns into its exit status. A 204 is `{}`."""
    headers = {config.TOKEN_HEADER: config.token()}
    url = f"http://127.0.0.1:{config.PORT}{path}"
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            answered = await client.request(method, url, headers=headers, **sent)
    except httpx.HTTPError as error:
        return {"error": f"the Deckhand daemon is not answering on port {config.PORT}: {error}",
                "code": "DAEMON_DOWN"}
    if answered.status_code >= 400:
        return {"error": f"the daemon refused that ({answered.status_code}): {_said(answered)}",
                "code": "REFUSED", "status": answered.status_code}
    if answered.status_code == 204:
        return {}
    try:
        return answered.json()
    except ValueError:
        return {"error": "the daemon answered with something that is not JSON",
                "code": "BAD_ANSWER"}
