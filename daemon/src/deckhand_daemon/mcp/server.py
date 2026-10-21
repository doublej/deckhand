"""The fourteen tools a session gets so it can reach the person, wherever they are.

The skill said all of this in prose first, and the prose is still the better half: a slip is a
file an agent writes in its own folder, and knowing that is worth more than any tool. These exist
because a tool is present whether or not the model thought to look, and the failure they answer is
a session that reached a decision needing the person and made it alone.

**Give the project a header, unasked.** If `<cwd>/.deckhand/header.jpg` (or `.png`/`.webp`) is
missing and the project already holds a picture that suits a wide banner — a logo, hero, screenshot,
cover art, not an icon-sized glyph — make one once, without asking the person: about 1200×360, under
300 KB, calm enough that a title reads over it (`sips --resampleWidth 1200 SRC --out TMP` then
`sips --cropToHeightWidth 360 1200 TMP --out .deckhand/header.jpg -s format jpeg`). Put `*` in
`.deckhand/.gitignore` if it is not there. The phone draws it faintly behind this session's title.
No suitable picture: do nothing, that is fine.

**Nine of the twelve are the daemon's own routes.** Nothing here reimplements one. `/say` carries
the session's filter chain, its orders and the delivery record; `/notify` carries the folder's
right to refuse being interrupted. Calling the functions underneath those routes would quietly
drop all of it, which is the shape of bug that looks like it works.

**Three of them are not routes at all.** `whoami` reads this session's own record. A slip is written in the session's own `cwd` and read back
from there, exactly as `docs/artifacts.md` chose — so `ask_on_phone` and `read_answer` run the
skill's own `slip.py` and `answer.py` rather than talking to the daemon. One copy of that logic,
and the tool and the shell command an agent might type produce the same file.

**What it refuses, and how.** By absence: there is no route argument, no `/control`, no `PUT`, and
no way to close a session — the whole list, with a reason each, closes these instructions. `say_to_session` is socket-only, because an agent choosing the keyboard
route is an agent claiming to be the person. None of this is a fence — the agent keeps `Bash` and
the token is a readable file — it is there so an agent does not *drift* into speaking as the
person because that route was the convenient one. `docs/agent-surface.md` says which token would
make these refusals real, and it does not exist yet.

**Five of them are the headset's space** (`docs/space.md`): `open_plane` puts a web page or a Mac
window beside this session, `close_plane` takes one away, `space` and `mac_windows` look, and
`start_session` brings another session in beside this one. A plane is furniture, so opening and
closing one is allowed. Starting a session is allowed because JJ asked for it (2026-10-14), and
only in a folder the listing names and Claude Code trusts — the gates the phone's own start has.
A session is never a plane the space keeps, so `close_plane` has nothing to name one by — closing
a session stays the person's own press.

**Two of them are the person's tmux** (`mcp/tmux.py`): `tmux_tree` reads every tmux session,
window and pane with the Claude session in each, and `tmux_arrange` renames, groups, moves, swaps,
joins, breaks, lays out, zooms and focuses them. Furniture again: nothing in it types into a pane
or closes one.

**`presence` comes first.** It says `laptop`, `headset` or `phone`. At the laptop the person is reading
this conversation, so ask in it; on the phone, ask there. Every tool here is also a `deckhand`
shell command (`mcp/cli.py`, `deckhand prime`), so a session without these tools loses nothing.
"""

from __future__ import annotations

import os
from typing import Literal
from urllib.parse import quote

from mcp.server.mcpserver import Context, MCPServer
from mcp.types import ToolAnnotations

from . import here, refused
from .here import match as _match
from .slips import ask_on_phone, read_answer
from .slips import folder as _folder
from .slips import nobody as _nobody
from .tmux import tmux_arrange, tmux_tree

READ_ONLY = ToolAnnotations(read_only_hint=True, open_world_hint=False)
WRITES = ToolAnnotations(open_world_hint=False)

class _Server(MCPServer):
    """The SDK's server, with the calling OpenCode session lifted out of each call's `_meta`.

    One override rather than a `Context` parameter on every tool: `here.mine()` is the one place
    a tool asks who it is, and it already sits under a dozen of them.
    """

    async def call_tool(self, name: str, arguments: dict, context: Context | None = None):
        meta = None
        try:
            meta = context.request_context.meta if context is not None else None
        except ValueError:
            pass  # no request behind this call, which is a test calling the tool directly
        asked = (meta or {}).get(here.OPENCODE_META)
        held = here.calling.set(asked if isinstance(asked, str) else "")
        try:
            return await super().call_tool(name, arguments, context)
        finally:
            here.calling.reset(held)


server = _Server(name="deckhand", instructions=(
    f"{__doc__}\n**Not here on purpose — the person's own, so stop looking:**\n"
    f"{refused.markdown()}\n"))
server.tool(annotations=READ_ONLY)(tmux_tree)
server.tool(annotations=WRITES)(tmux_arrange)


@server.tool(annotations=READ_ONLY)
async def whoami() -> dict:
    """Which session this is: its id, its name, the folder it is working in."""
    held, why = _folder()
    if held is None:
        return _nobody(why)
    return {"session": held["sessionId"], "name": held.get("name", ""),
            "folder": held.get("cwd", ""), "status": held.get("status", "")}


server.tool(annotations=WRITES)(ask_on_phone)
server.tool(annotations=READ_ONLY)(read_answer)


@server.tool(annotations=READ_ONLY)
async def presence() -> dict:
    """Where the person is right now. `where` is `laptop` — at this Mac, reading this
    conversation, so ask here — `headset`, reading it on a pane in the headset, so ask here too —
    or `phone`: away from it, so `ask_on_phone`, or `call_for_attention` for something they must
    see. Ask again before each question; it moves
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
    """Every session live on this Mac — Claude Code, Codex or OpenCode: its name, folder,
    whether it is busy, how many slips it has left waiting for the person, and its `provider`. A
    `codex` thread is listed but takes no agent's words, so `say_to_session` refuses it; an
    `opencode` session takes them, labelled as not from its user."""
    answered = await here.reach("GET", "/sessions")
    if "error" in answered:
        return answered
    return {"sessions": [
        {"session": s.get("session_id"), "name": s.get("name"), "folder": s.get("cwd"),
         "status": s.get("status"), "waiting": s.get("artifacts_waiting", 0),
         "provider": s.get("provider", "claude")}
        for s in answered.get("sessions", [])
    ]}


@server.tool(annotations=WRITES)
async def say_to_session(session: str, text: str) -> dict:
    """Say something to another session on this Mac, by name or by id.

    It arrives down that session's peer inbox — or, for an OpenCode session, as OpenCode's
    synthetic input — labelled as coming from another agent and carrying none of your user's
    authority, which is the only way an agent may speak to one. It
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
    `id` is what `close_plane` takes. Opening what is already open beside you hands back that
    plane with `reused: true` rather than a second copy, so a retry is safe.
    """
    if (url is None) == (window is None):
        return {"error": "give exactly one of url or window", "code": "BAD_PLANE"}
    sent: dict = {"kind": "web", "url": url} if url is not None else {"kind": "window",
                                                                        "window": window}
    if title:
        sent["title"] = title
    if held := here.mine():
        sent |= {"near": held["sessionId"], "by": _by(held)}
    return await here.reach("POST", "/space/planes", json=sent)


def _by(held: dict) -> str:
    """Who an agent's plane says did it. Never empty: no `by` is the person, to the daemon."""
    return held.get("name") or held["sessionId"]


@server.tool(annotations=READ_ONLY)
async def space(full: bool = False) -> dict:
    """Where you are in the person's headset and what is around you. `around_you` is your pose,
    your group, and every session, page and window `beside` you — in your group or opened near
    you. `planes` is every page and window open: id, kind, url or window, title, the session it is
    `near` and who opened it (`by` null is the person). `full` adds every kept pose, which is
    room coordinates and rarely what you need."""
    whole = await here.reach("GET", "/space")
    if "error" in whole:
        return whole
    seen = {"planes": whole["planes"]} | ({"poses": whole["poses"], "rev": whole["rev"]} if full else {})
    if held := here.mine():
        seen = {"around_you": await here.reach("GET", f"/sessions/{held['sessionId']}/space")} | seen
    return seen


#: How many startable folders a refusal lists — enough to pick from, never the whole Mac.
STARTABLE_SHOWN = 10


async def _startable(near: str) -> str:
    """The folders a session can be started in, the ones closest to `near` first."""
    listed = await here.reach("GET", "/projects")
    if "error" in listed:
        return ""
    paths = [p["path"] for p in listed.get("projects", []) if p.get("trusted")]
    # Leading folders in common, counted by hand: another machine's folders (`C:\dev\…` on
    # Fractal) are not POSIX paths, and `os.path.commonpath` raises on them.
    def shared(path: str) -> int:
        return next((i for i, (a, b) in enumerate(zip(path.split("/"), near.split("/"))) if a != b),
                    min(path.count("/"), near.count("/")) + 1)
    paths.sort(key=lambda p: (-shared(p), p))
    more = f" (+{len(paths) - STARTABLE_SHOWN} more)" if len(paths) > STARTABLE_SHOWN else ""
    return " — startable: " + ", ".join(paths[:STARTABLE_SHOWN]) + more if paths else ""


@server.tool(annotations=WRITES)
async def start_session(folder: str | None = None,
                        provider: Literal["claude", "codex", "opencode"] = "claude") -> dict:
    """Start another Claude Code session, standing beside you in the person's headset in your
    group — to hand it part of the work, or to show the person something running. `folder`
    defaults to your own; it must be a project the Mac lists and Claude Code already trusts, or
    the answer says why not. It starts with no task: tell it what to do with `say_to_session`,
    which reaches it as an agent. You cannot close it afterwards — that is the person's."""
    held = here.mine()
    if not held:
        return _nobody("a session starts beside the session asking, and none is above this process")
    # Relative to this session's folder, never to wherever this process was started.
    path = os.path.normpath(os.path.join(held.get("cwd", ""), folder or "."))
    started = await here.reach("POST", "/space/sessions", json={
        "near": held["sessionId"], "path": path, "provider": provider})
    if started.get("status") in (400, 409):
        return {"error": started["error"] + await _startable(path), "code": "NOT_STARTABLE"}
    return started


@server.tool(annotations=WRITES)
async def close_plane(id: str) -> dict:
    """Close a plane in the person's headset, by the id `open_plane` or `space` gave — a unique
    prefix of it is enough. Only a web page or a Mac window: an agent can never close a session,
    and nothing here names one. Closed as you, so the session it stood beside is not told the
    person took it away."""
    whole = await here.reach("GET", "/space")
    if "error" in whole:
        return whole
    planes = whole["planes"]
    found = [p for p in planes if p["id"].startswith(id)] if id else []
    if len(found) != 1:
        listed = ", ".join(f"{p['id'][:8]} {p['title']}" for p in planes) or "none open"
        which = "more than one plane starts" if found else "no plane starts"
        return {"error": f"{which} with {id!r} — open: {listed}", "code": "NO_SUCH_PLANE"}
    # No session above is the person at a terminal, and the daemon treats no `by` as the person.
    by = {"by": _by(held)} if (held := here.mine()) else {}
    answered = await here.reach("DELETE", f"/space/planes/{quote(found[0]['id'], safe='')}",
                                params=by)
    return answered if "error" in answered else {"closed": found[0]["id"]}


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
