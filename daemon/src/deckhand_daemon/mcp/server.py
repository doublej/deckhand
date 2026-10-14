"""The eleven tools a session gets so it can reach the person, wherever they are.

The skill said all of this in prose first, and the prose is still the better half: a slip is a
file an agent writes in its own folder, and knowing that is worth more than any tool. These exist
because a tool is present whether or not the model thought to look, and the failure they answer is
a session that reached a decision needing the person and made it alone.

**Nine of the eleven are the daemon's own routes.** Nothing here reimplements one. `/say` carries the
session's filter chain, its orders and the delivery record; `/notify` carries the folder's right to
refuse being interrupted. Calling the functions underneath those routes would quietly drop all of
it, which is the shape of bug that looks like it works.

**Two of them are not routes at all.** A slip is written in the session's own `cwd` and read back
from there, exactly as `docs/artifacts.md` chose — so `ask_on_phone` and `read_answer` run the
skill's own `slip.py` and `answer.py` rather than talking to the daemon. One copy of that logic,
and the tool and the shell command an agent might type produce the same file.

**What it refuses, and how.** By absence: there is no route argument, no `/control`, no `PUT`, no
`POST /projects/session`. `say_to_session` is socket-only, because an agent choosing the keyboard
route is an agent claiming to be the person. None of this is a fence — the agent keeps `Bash` and
the token is a readable file — it is there so an agent does not *drift* into speaking as the
person because that route was the convenient one. `docs/agent-surface.md` says which token would
make these refusals real, and it does not exist yet.

**Four of them are the headset's space** (`docs/space.md`): `open_plane` puts a web page or a Mac
window beside this session, `close_plane` takes one away, `space` and `mac_windows` look. A plane
is furniture, so opening and closing one is allowed. A session is never a plane the space keeps,
so `close_plane` has nothing to name one by — closing a session stays the person's own press.

**`presence` comes first.** It says `laptop` or `phone`. At the laptop the person is reading
this conversation, so ask in it; on the phone, ask there. Every tool here is also a `deckhand`
shell command (`mcp/cli.py`, `deckhand prime`), so a session without these tools loses nothing.
"""

from __future__ import annotations

import asyncio
import json
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote

from mcp.server.mcpserver import MCPServer
from mcp.types import ToolAnnotations

from . import here

# The skill's own scripts, from this repo rather than from `~/.claude/skills/deckhand` — the same
# files either way, since that is a symlink, and this way a checkout that has not been installed
# still works. `templates/` beside them are symlinks into `demos/`, so there is one copy of every
# page and `just demo-check` gates it.
SCRIPTS = Path(__file__).resolve().parents[4] / "skills" / "deckhand" / "scripts"
# A slip nobody answers should not hold a tool call open forever, and Claude Code's own tool
# timeout is well under this anyway — so the default is to look once and let the daemon's message
# wake the session when the answer lands.
MAX_WAIT = 600.0
READ_ONLY = ToolAnnotations(read_only_hint=True, open_world_hint=False)
WRITES = ToolAnnotations(open_world_hint=False)

server = MCPServer(name="deckhand", instructions=__doc__)


async def _script(name: str, *args: str) -> tuple[bool, str]:
    """Run one of the skill's scripts. Returns (it worked, what it printed).

    In a subprocess rather than imported: both scripts end an argument they dislike with
    `sys.exit(sentence)`, which is right for a command and would take this server down with it.
    """
    done = await asyncio.to_thread(
        subprocess.run, [sys.executable, str(SCRIPTS / name), *args],
        capture_output=True, text=True, check=False, timeout=MAX_WAIT + 30,
    )
    return done.returncode == 0, (done.stdout or done.stderr).strip()


NO_SESSION = ("this is not running inside a Claude Code session, so there is no folder to write "
              "a slip in and no session to speak as")


def _folder() -> tuple[dict, str] | tuple[None, str]:
    """This session's record and its folder, or a sentence saying there is no session above."""
    held = here.mine()
    if held is None:
        return None, NO_SESSION
    return held, held.get("cwd", "")


def _nobody(why: str) -> dict:
    return {"error": why, "code": "NO_SESSION"}


def _match(wanted: str, live: list[dict]) -> dict | None:
    """By id or name exactly, else by the one id it begins or the one name it is part of —
    `say utt` should not need the whole of `utt-review`. Two candidates is no match."""
    for exact in (s for s in live if wanted in (s.get("session_id"), s.get("name"))):
        return exact
    near = [s for s in live if (s.get("session_id") or "").startswith(wanted)
            or wanted.lower() in (s.get("name") or "").lower()]
    return near[0] if len(near) == 1 else None


@server.tool(annotations=READ_ONLY)
async def whoami() -> dict:
    """Which session this is: its id, its name, the folder it is working in."""
    held, why = _folder()
    if held is None:
        return _nobody(why)
    return {"session": held["sessionId"], "name": held.get("name", ""),
            "folder": held.get("cwd", ""), "status": held.get("status", "")}


@server.tool(annotations=WRITES)
async def ask_on_phone(question: str, kind: str = "confirm", options: list[str] | None = None,
                       note: str = "", questions: list[str] | None = None) -> dict:
    """Ask the person a question on their phone. Returns the slip's id, to read the answer by.

    `kind` is one of confirm, pick, text, aloud. `options` is the yes label then the no label for
    a confirm, one row per choice for a pick, and the field's label for a text. `questions` is for
    an aloud slip only, each one `id:the question`, and the person answers by speaking.

    The page is written into this session's own folder and appears on the phone within seconds.
    Asking the same question again replaces the page and drops any answer already given to it.
    """
    held, why = _folder()
    if held is None:
        return _nobody(why)
    if kind not in ("confirm", "pick", "text", "aloud"):
        return {"error": f"{kind!r} is not a kind of slip — confirm, pick, text or aloud",
                "code": "BAD_KIND"}
    args = ["--kind", kind, "--title", question, "--dir", why, "--session", held["sessionId"]]
    if note:
        args += ["--note", note]
    for choice in options or []:
        args += ["--option", choice]
    for asked in questions or []:
        args += ["--question", asked]
    worked, said = await _script("slip.py", *args)
    if not worked:
        return {"error": said, "code": "REFUSED"}
    return {"id": Path(said).stem, "title": question, "waiting": True, "page": said}


@server.tool(annotations=READ_ONLY)
async def read_answer(id: str, wait_seconds: float = 0.0) -> dict:
    """What the person answered on a slip, if they have. `wait_seconds` blocks for up to ten
    minutes; left out it looks once, which is usually right because the daemon messages this
    session the moment an answer lands."""
    held, why = _folder()
    if held is None:
        return _nobody(why)
    waited = max(0.0, min(float(wait_seconds), MAX_WAIT))
    worked, said = await _script("answer.py", id, "--wait", str(waited), "--dir", why,
                                 "--session", held["sessionId"])
    if not worked:
        return {"answered": False, "why": said}
    try:
        return {"answered": True, "value": json.loads(said)}
    except json.JSONDecodeError:
        return {"answered": True, "value": said}


@server.tool(annotations=READ_ONLY)
async def presence() -> dict:
    """Where the person is right now. `where` is `laptop` — at this Mac, reading this
    conversation, so ask here — or `phone`: away from it, so `ask_on_phone`, or
    `call_for_attention` for something they must see. Ask again before each question; it moves
    the moment they sit down or walk off."""
    return await here.reach("GET", "/presence")


@server.tool(annotations=WRITES)
async def call_for_attention(line: str) -> dict:
    """Ask for the person outright, in your own words — a card on their Lock Screen.

    For when a long job has finished with nobody watching or this session is stuck. The folder may
    refuse to be interrupted, and the refusal comes back as `pushed: false` with the reason: say so
    rather than carrying on as though they have seen it.
    """
    held, why = _folder()
    if held is None:
        return _nobody(why)
    return await here.reach("POST", f"/sessions/{held['sessionId']}/notify", json={"line": line})


@server.tool(annotations=READ_ONLY)
async def sessions() -> dict:
    """Every Claude Code session live on this Mac: its name, folder, whether it is busy, and how
    many slips it has left waiting for the person."""
    answered = await here.reach("GET", "/sessions")
    if "error" in answered:
        return answered
    return {"sessions": [
        {"session": s.get("session_id"), "name": s.get("name"), "folder": s.get("cwd"),
         "status": s.get("status"), "waiting": s.get("artifacts_waiting", 0)}
        for s in answered.get("sessions", [])
    ]}


@server.tool(annotations=WRITES)
async def say_to_session(session: str, text: str) -> dict:
    """Say something to another session on this Mac, by name or by id.

    It arrives down that session's peer inbox, labelled as coming from another Claude session and
    carrying none of your user's authority — which is the only way an agent may speak to one. It
    can be stopped by that session's filters, so read the receipt: `went: false` means it was not
    said, whatever the reason beside it.
    """
    listed = await here.reach("GET", "/sessions")
    if "error" in listed:
        return listed
    live = listed.get("sessions", [])
    match = _match(session, live)
    if match is None:
        return {"went": False, "code": "NO_SUCH_SESSION",
                "why": f"no one live session called {session!r} — "
                       f"there is {', '.join(s.get('name', '?') for s in live)}"}
    if match.get("provider") == "codex":
        return {"went": False, "code": "CODEX_THREAD", "why": f"{match.get('name')} is a Codex thread: its only way in "
                                      f"carries the person's own authority, so no agent speaks "
                                      f"into it"}
    answered = await here.reach("POST", f"/sessions/{match['session_id']}/say",
                                params={"route": "socket"}, json={"text": text})
    if "error" in answered:
        return {"went": False, "code": answered["code"], "why": answered["error"]}
    stopped = answered.get("stopped_by")
    return {"went": bool(answered.get("delivered")), "by": answered.get("delivered_by"),
            "why": answered.get("delivery_error")
            or (f"the {stopped} filter stopped it" if stopped else None)}


@server.tool(annotations=WRITES)
async def open_plane(url: str | None = None, window: int | None = None,
                     title: str | None = None) -> dict:
    """Open a web page, or one of this Mac's windows, as a plane beside this session in the
    person's headset. Give exactly one: `url`, or `window` — an id from `mac_windows`.

    The headset is another machine on the LAN, so the URL has to be reachable from there. Prefer
    the project's atlas dev hostname, `https://<slug>.atlas.local.jurrejan.com`. A localhost URL
    is rewritten to this Mac's LAN address, which only works if the server binds 0.0.0.0. A Mac
    window plane is view-only: the person sees it and cannot click into it.

    What the person says while looking at the plane comes to this session. Returns the plane; its
    `id` is what `close_plane` takes.
    """
    if (url is None) == (window is None):
        return {"error": "give exactly one of url or window", "code": "BAD_PLANE"}
    sent: dict = {"kind": "web", "url": url} if url is not None else {"kind": "window",
                                                                        "window": window}
    if title:
        sent["title"] = title
    if held := here.mine():
        sent |= {"near": held["sessionId"], "by": held.get("name") or None}
    return await here.reach("POST", "/space/planes", json=sent)


@server.tool(annotations=READ_ONLY)
async def space() -> dict:
    """What is open in the person's headset besides the sessions — each plane's id, kind, url or
    window, title, the session it is `near` and who opened it — and where every plane is."""
    return await here.reach("GET", "/space")


@server.tool(annotations=WRITES)
async def close_plane(id: str) -> dict:
    """Close a plane in the person's headset, by the id `open_plane` or `space` gave. Only a web
    page or a Mac window: an agent can never close a session, and nothing here names one."""
    answered = await here.reach("DELETE", f"/space/planes/{quote(id, safe='')}")
    return answered if "error" in answered else {"closed": id}


@server.tool(annotations=READ_ONLY)
async def mac_windows() -> dict:
    """This Mac's windows, each with the `id` `open_plane` takes, its app, title and size. Says
    why when the window helper is not running."""
    answered = await here.reach("GET", "/windows")
    return {"windows": answered} if isinstance(answered, list) else answered


def main() -> None:
    server.run("stdio")


if __name__ == "__main__":
    main()
