"""The headset's groups and tmux's `@group`, kept the same both ways.

A session is in a group in the headset when its kept pose carries a `group`; in tmux when its
window carries the window option `@group`, the group's name, and maybe `@group_color`. tmux is
where groups outlive an iTerm crash, and a launchd agent outside deckhand keeps iTerm's tab groups
the same as `@group` — so deckhand never talks to iTerm. The person makes a group on either side,
so each pass compares both against what they were when they last agreed (`tmux-groups.json`,
`{session id: {"d": group, "i": @group}}`) and carries whichever one moved. When both moved, tmux
wins.

- **Into tmux** a group becomes one `@group` on every member's window: the name a member that did
  not move already has, else its project's, with " 2" on it when another group has that one.
  `@group_color` is the project's colour, written only where no member's window has one.
- **Into the headset** an `@group` is the same `beside` a started session uses: the session's
  pose is dropped and it stands beside a session already in that group, so the headset puts it
  flush there. With nobody there yet, the first of them is the one the rest stand beside. A
  window alone with its `@group` is no group in the headset, and stays named in tmux.
- **Names come from tmux** (`names` in `space.json`): whoever renames writes `@group` on every
  window in the group, and the headset titles the group with it. A whole headset group moving
  to one new `@group` is that rename, and nothing in the headset moves.
- `@group` is per window, so a window holding two sessions follows the last one to move.
"""

from __future__ import annotations

import asyncio
import json
import subprocess
from pathlib import Path

from .. import config, sessions
from ..log import log
from ..sessions import project
from . import stored

POLL = 3.0
STATE = "tmux-groups.json"
TIMEOUT = 5
#: One window per line: its id, its `@group` and its `@group_color`, either empty when unset.
FORMAT = "#{window_id}\t#{@group}\t#{@group_color}"

Now = dict[str, tuple[str | None, str | None]]  # session id → (headset group, @group)


async def watch() -> None:
    """Runs beside the other watchers; a pass with no tmux server does nothing."""
    while True:
        await asyncio.sleep(POLL)
        try:
            await asyncio.to_thread(sync)
        except (OSError, subprocess.SubprocessError) as error:
            log.warning("tmux group sync failed: %s", error)


def decide(now: Now, last: dict[str, dict]) -> tuple[dict[str, str | None], dict[str, str | None]]:
    """Which side moved since the two last agreed: `({session: group} for tmux, {session: @group}
    for the headset)`. A session never seen before carries whichever side has one."""
    to_tmux: dict[str, str | None] = {}
    to_headset: dict[str, str | None] = {}
    for sid, (d, i) in now.items():
        was = last.get(sid)
        if was is None:
            # Both sides already have one: take them as agreeing rather than move anything.
            if i is not None and d is None:
                to_headset[sid] = i
            elif d is not None and i is None:
                to_tmux[sid] = d
        elif i != was["i"]:
            to_headset[sid] = i
        elif d != was["d"]:
            to_tmux[sid] = d
    return to_tmux, to_headset


def pull(now: Now, to_headset: dict[str, str | None]) -> dict[str, str | None]:
    """Moves the headset's groups to match tmux's; each moved session's group as `space.json`
    holds it right after."""
    after: dict[str, str | None] = {}
    for sid in [s for s, v in to_headset.items() if v is None]:
        stored.ungroup(sid)
        after[sid] = None
    for i in {i for i in to_headset.values() if i is not None}:
        movers = sorted(s for s, v in to_headset.items() if v == i)
        # Someone already in that @group, one in a headset group first.
        stayers = sorted((d is None, s) for s, (d, ii) in now.items() if ii == i and s not in to_headset)
        held = {now[s][0] for s in movers} - {None}
        if not stayers and len(held) == 1 and all(s in movers for s, (d, _) in now.items() if d in held):
            # One whole headset group under a new name is a rename: it stays where it stands, and
            # only who was in no headset group comes to stand beside it.
            stayers = [(False, s) for s in movers if now[s][0] in held]
            movers = [s for s in movers if now[s][0] is None]
        if stayers:
            mate = stayers[0][1]
            movers = [s for s in movers if now[s][0] is None or now[s][0] != now[mate][0]]
        else:
            # Nobody: the first one leaves its own group and the rest stand beside it. Alone, it
            # only leaves.
            mate, movers = movers[0], movers[1:]
            stored.ungroup(mate)
            after[mate] = None
        for sid in movers:
            stored.regroup(sid, mate)
            after[sid] = None
    return after


def push(now: Now, windows: dict[str, str], groups: dict[str, str | None], to_tmux: dict[str, str | None],
         colors: dict[str, str], projects: dict[str, dict]) -> None:
    """Moves tmux's `@group` to match the headset's groups."""
    for sid, d in to_tmux.items():
        if d is None and now[sid][1] is not None:
            _set(windows[sid], "@group", None)
    for d in sorted({d for d in to_tmux.values() if d is not None}):
        members = sorted(s for s, g in groups.items() if g == d and s in windows)
        stayed = [now[s][1] for s in members if s not in to_tmux and now[s][1]]
        taken = {i for s, (_, i) in now.items() if i and s not in members}
        name = stayed[0] if stayed else fresh(projects[members[0]]["key"].rsplit("/", 1)[-1], taken)
        color = next((c for s in members if (c := colors.get(windows[s]))), None)
        for sid in members:
            if now[sid][1] != name:
                _set(windows[sid], "@group", name)
            if color is None:
                _set(windows[sid], "@group_color", projects[sid]["color"])


def fresh(base: str, taken: set[str]) -> str:
    """`base`, or `base 2`, `base 3`… — the first another group does not already have."""
    base = base or "deckhand"
    name, n = base, 1
    while name in taken:
        n += 1
        name = f"{base} {n}"
    return name


def sync() -> None:
    """One pass: read both sides, carry what moved, write down where they now agree."""
    live = [s for s in sessions.live_sessions() if s.pane is not None and s.provider == "claude"]
    windows = {s.session_id: s.pane.window_id for s in live}
    read = _windows()
    if read is None:
        return
    poses = stored.space()["poses"]
    groups = {sid: (poses.get(f"session:{sid}") or {}).get("group") for sid in windows}
    now = {sid: (groups[sid], read[w][0]) for sid, w in windows.items() if w in read}  # not found is not "left"
    path = config.data_dir() / STATE
    last = _load(path)
    to_tmux, to_headset = decide(now, last)
    after = pull(now, to_headset)
    if to_tmux:
        projects = {s.session_id: project.of(s.cwd) for s in live}
        push(now, windows, groups, to_tmux, {w: c for w, (_, c) in read.items() if c}, projects)
        read = _windows() or read
        now = {sid: (d, read.get(windows[sid], (i,))[0]) for sid, (d, i) in now.items()}
        log.info("tmux groups: %d into tmux, %d into the headset", len(to_tmux), len(to_headset))
    elif to_headset:
        log.info("tmux groups: %d into the headset", len(to_headset))
    agreed = {sid: was for sid, was in last.items() if sid in windows}  # unseen this pass: as they were
    agreed |= {sid: {"d": after.get(sid, d), "i": i} for sid, (d, i) in now.items()}
    if agreed != last:
        path.write_text(json.dumps(agreed, indent=2) + "\n")
    stored.name({a["d"]: a["i"] for a in agreed.values() if a["d"] and a["i"]})


def parse(listing: str) -> dict[str, tuple[str | None, str | None]]:
    """`FORMAT`'s lines as window id → (`@group`, `@group_color`), None where unset."""
    found: dict[str, tuple[str | None, str | None]] = {}
    for line in listing.splitlines():
        window, group, color = (line.split("\t", 2) + ["", ""])[:3]
        if window:
            found[window] = (group or None, color or None)
    return found


def _windows() -> dict[str, tuple[str | None, str | None]] | None:
    """Every tmux window's group, or None when no tmux server answers."""
    out = subprocess.run(["tmux", "list-windows", "-a", "-F", FORMAT],
                         capture_output=True, text=True, timeout=TIMEOUT, check=False)
    return parse(out.stdout) if out.returncode == 0 else None


def _set(window: str, option: str, value: str | None) -> None:
    """One window option set, or unset when `value` is None."""
    flags, values = ("-w", [value]) if value is not None else ("-wu", [])
    subprocess.run(["tmux", "set-option", flags, "-t", window, option, *values],
                   capture_output=True, timeout=TIMEOUT, check=False)


def _load(path: Path) -> dict[str, dict]:
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return {}
