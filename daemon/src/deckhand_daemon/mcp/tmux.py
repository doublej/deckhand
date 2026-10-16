"""tmux, for an agent tidying the person's terminal: the whole tree, and its furniture moved.

**Furniture, never the keys.** Renaming a window, grouping it, moving, swapping, joining two panes
into one window or breaking one out, a layout, a zoom, a focus — none of it reaches what runs in
a pane. `send-keys` would be the keyboard route, and `kill-*` or `respawn-pane` would close a
session; those are the person's (`refused.py`), and there is no action here to name them by.

**Run here, not through the daemon.** This process is a child of `claude` in its pane, so `$TMUX`
already names the server the person attaches to, on whichever machine this session runs. There
is no route to go through and nothing like a filter chain to drop by not using one. The daemon is
asked only which Claude session sits in which pane; a daemon that is down leaves the tree
unlabelled rather than empty.

**`@group` is the headset's too.** `space/groups.py` carries a window's `@group` into the headset
within three seconds, so `group` is also how sessions come to stand together there. A pane broken
out keeps the group of the window it left, or the headset would read that as leaving it.
"""

from __future__ import annotations

import asyncio
import os
import subprocess
from typing import Literal

from . import here

#: The command, as a tuple so a test can point it at a server of its own with `-L`.
TMUX: tuple[str, ...] = ("tmux",)
TIMEOUT = 10
FIELDS = ("session_name", "session_attached", "window_id", "window_index", "window_name",
          "@group", "window_active", "window_zoomed_flag", "pane_id", "pane_active",
          "pane_width", "pane_height", "pane_current_command", "pane_current_path")
FORMAT = "\t".join(f"#{{{field}}}" for field in FIELDS)
LAYOUTS = ("tiled", "even-horizontal", "even-vertical", "main-horizontal", "main-vertical")
Action = Literal["rename", "group", "ungroup", "move", "swap", "join", "break", "layout", "zoom",
                 "focus"]
#: What each action needs beside `target`, said back when it is missing.
NEEDS = {"rename": "name", "group": "name", "move": "to", "swap": "to", "join": "to",
         "layout": "layout"}


async def _tmux(*args: str) -> tuple[bool, str]:
    """One tmux command. Returns (it worked, what it printed, or why not)."""
    try:
        done = await asyncio.to_thread(subprocess.run, [*TMUX, *args], capture_output=True,
                                       text=True, timeout=TIMEOUT, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        return False, f"tmux did not run: {error}"
    return done.returncode == 0, (done.stdout if done.returncode == 0 else done.stderr).strip()


async def _rows() -> list[dict] | dict:
    """Every pane, as one dict of `FIELDS` each, or the error when no tmux server answers."""
    ok, said = await _tmux("list-panes", "-a", "-F", FORMAT)
    if not ok:
        return {"error": f"no tmux server answers here: {said}", "code": "NO_TMUX"}
    return [dict(zip(FIELDS, line.split("\t"))) for line in said.splitlines()]


async def _labels() -> dict[str, dict]:
    """pane id → the Claude session in it, from the daemon's listing; empty when it is down."""
    listed = await here.reach("GET", "/sessions")
    if "error" in listed:
        return {}
    return {s["pane"]["iterm_session_id"]: s for s in listed.get("sessions", []) if s.get("pane")}


def find(target: str, rows: list[dict], labels: dict[str, dict]) -> dict | None:
    """The one pane `target` names, as its row. `%3` is a pane; `@2`, `main:4` and `main:logs`
    are a window; a bare word is a Claude session's exact name or id, else a window's name, else
    the one session whose name it is part of. A window is its active pane. Two candidates is no
    match, never a guess."""
    if target[:1] in ("%", "@"):
        found = [r for r in rows if target in (r["pane_id"], r["window_id"])]
    elif ":" in target:
        place, _, window = target.partition(":")
        found = [r for r in rows if r["session_name"] == place
                 and window in (r["window_index"], r["window_name"])]
    else:
        found = [r for r in rows if r["window_name"] == target]
        held = here.match(target, list(labels.values()))
        if held and (not found or target in (held.get("name"), held.get("session_id"))):
            found = [r for r in rows if r["pane_id"] == held["pane"]["iterm_session_id"]]
    if len({r["window_id"] for r in found}) != 1:
        return None
    return next((r for r in found if r["pane_active"] == "1"), found[0])


def tree(rows: list[dict], labels: dict[str, dict]) -> list[dict]:
    """The rows as tmux sessions → windows → panes, each pane named by the session in it."""
    sessions: dict[str, dict] = {}
    for r in rows:
        place = sessions.setdefault(r["session_name"], {
            "name": r["session_name"], "attached": r["session_attached"] != "0", "windows": {}})
        window = place["windows"].setdefault(r["window_id"], {
            "id": r["window_id"], "index": int(r["window_index"]), "name": r["window_name"],
            "group": r["@group"] or None, "active": r["window_active"] == "1",
            "zoomed": r["window_zoomed_flag"] == "1", "panes": []})
        pane = {"id": r["pane_id"], "active": r["pane_active"] == "1",
                "size": f"{r['pane_width']}x{r['pane_height']}",
                "command": r["pane_current_command"], "folder": r["pane_current_path"]}
        if held := labels.get(r["pane_id"]):
            pane |= {"session": held.get("name"), "session_id": held.get("session_id"),
                     "status": held.get("status")}
        window["panes"].append(pane)
    return [place | {"windows": list(place["windows"].values())} for place in sessions.values()]


async def tmux_tree() -> dict:
    """The person's whole tmux, to organise it with `tmux_arrange`: every tmux session, its
    windows (id, index, name, `group`, active, zoomed) and their panes (id, size, the command
    running, its folder, and the Claude session in it by name, id and status). `you` is the pane
    this session is in."""
    rows = await _rows()
    if isinstance(rows, dict):
        return rows
    # Under OpenCode this server is the service's child, not a pane's: the `TMUX_PANE` it
    # inherited is whichever pane started `opencode serve`, and naming it would be a lie.
    you = None if here.calling.get() else os.environ.get("TMUX_PANE")
    return {"you": you, "sessions": tree(rows, await _labels())}


async def tmux_arrange(action: Action, target: str, to: str | None = None,
                       name: str | None = None, layout: str | None = None,
                       split: Literal["right", "below"] = "right") -> dict:
    """Move the furniture of the person's tmux — never what runs in it. `target` and `to` are a
    Claude session's name or id (its pane), a pane `%3`, a window `@2`, `session:index`,
    `session:name` or a window name; `tmux_tree` shows them all.

    - `rename` the target's window to `name`.
    - `group` its window under `name` (tmux's `@group`, which the headset follows within
      seconds: grouped sessions stand together there); `ungroup` drops it.
    - `move` its window to just after `to`'s, or to the end of tmux session `to`.
    - `swap` its window with `to`'s.
    - `join` its pane into `to`'s window, `split` to the right or below — two sessions side by
      side. `break` takes a pane out into a window of its own, called `name` if given, keeping
      its group.
    - `layout` the target's window: tiled, even-horizontal, even-vertical, main-horizontal or
      main-vertical. `zoom` toggles its pane filling the window.
    - `focus` shows the target in the person's terminal: it moves what they are looking at, so
      only when they asked.

    Nothing here types into a pane or closes one; those are the person's.
    """
    if action in NEEDS and not {"name": name, "to": to, "layout": layout}[NEEDS[action]]:
        return {"error": f"{action} needs {NEEDS[action]}", "code": "BAD_ARRANGE"}
    if action == "layout" and layout not in LAYOUTS:
        return {"error": f"{layout!r} is not a layout — {', '.join(LAYOUTS)}",
                "code": "BAD_ARRANGE"}
    rows = await _rows()
    if isinstance(rows, dict):
        return rows
    labels = await _labels()
    found = find(target, rows, labels)
    # A tmux session's own name, for `move`, before anything a bare word could be part of.
    to_end = action == "move" and to in {r["session_name"] for r in rows}
    wants = NEEDS.get(action) == "to" and not to_end
    there = find(to, rows, labels) if wants else None
    if found is None or (wants and there is None):
        missing = target if found is None else to
        return {"error": f"nothing in tmux is one {missing!r} — `tmux_tree` lists what is",
                "code": "NO_SUCH_TARGET"}
    pane, window = found["pane_id"], found["window_id"]
    match action:
        case "rename":
            steps = [("rename-window", "-t", window, name)]
        case "group":
            steps = [("set-option", "-w", "-t", window, "@group", name)]
        case "ungroup":
            steps = [("set-option", "-wu", "-t", window, "@group")]
        case "move" if to_end:
            steps = [("move-window", "-d", "-s", window, "-t", f"{to}:")]
        case "move":
            steps = [("move-window", "-d", "-a", "-s", window, "-t", there["window_id"])]
        case "swap":
            steps = [("swap-window", "-d", "-s", window, "-t", there["window_id"])]
        case "join":
            steps = [("join-pane", "-d", "-h" if split == "right" else "-v", "-s", pane,
                      "-t", there["pane_id"])]
        case "break":
            steps = [("break-pane", "-d", "-P", "-F", "#{window_id}", "-s", pane,
                      *(("-n", name) if name else ()))]
        case "layout":
            steps = [("select-layout", "-t", window, layout)]
        case "zoom":
            steps = [("resize-pane", "-Z", "-t", pane)]
        case "focus":
            steps = [("select-window", "-t", pane), ("select-pane", "-t", pane)]
        case _:
            return {"error": f"{action!r} is not an arrangement", "code": "BAD_ARRANGE"}
    said = ""
    for step in steps:
        ok, said = await _tmux(*step)
        if not ok:
            return {"error": f"tmux refused {step[0]}: {said}", "code": "TMUX_REFUSED"}
    if action == "break":
        window = said
        if found["@group"]:
            await _tmux("set-option", "-w", "-t", window, "@group", found["@group"])
    return {"done": action, "pane": pane, "window": window}
