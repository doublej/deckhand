"""The headset's groups and iTerm's tab groups, kept the same both ways.

A session is in a group in the headset when its kept pose carries a `group`; its tab is in a
group in iTerm (3.7 and newer) when the tab bar draws it under a chip. The person makes either
by hand, so neither side owns the answer: each pass compares both against what they were when
they last agreed (`iterm-groups.json`, `{session id: {"d": group, "i": tab group}}`) and carries
whichever one moved over to the other. When both moved, the headset wins.

- **Into iTerm** a group becomes one tab group per window, named for its project and in its
  colour — iTerm cannot group tabs across windows. A group of one is no tab group.
- **Into the headset** a tab group is the same `beside` a started session uses: the session's
  pose is dropped and it stands beside a session already in that group, so the headset puts it
  flush there. With nobody there yet, the first of them is the one the rest stand beside, and the
  headset names the group. Until the headset is on, nothing there moves, and nothing here waits.
- **Names go one way, iTerm's into the headset** (`names` in `space.json`): only iTerm can rename a
  group. A group made from the headset starts out named for its project, as the headset titles it.
- **Only through the iTerm API connection** `iterm.py` holds, so only once that is approved. A
  tab holding two sessions follows the last one to move.
"""

from __future__ import annotations

import asyncio
import json
from collections import Counter
from pathlib import Path
from typing import Any

from .. import config, sessions
from ..log import log
from ..sessions import project
from . import iterm, stored

POLL = 3.0
STATE = "iterm-groups.json"

Now = dict[str, tuple[str | None, str | None]]  # session id → (headset group, tab group)


async def watch() -> None:
    """Runs beside the other watchers; idle until the iTerm API is approved."""
    while True:
        await asyncio.sleep(POLL)
        if iterm.ready():
            try:
                await asyncio.to_thread(sync)
            except OSError as error:
                log.warning("tab group sync failed: %s", error)


def decide(now: Now, last: dict[str, dict]) -> tuple[dict[str, str | None], dict[str, str | None]]:
    """Which side moved since the two last agreed: `({session: group} for iTerm, {session: tab
    group} for the headset)`. A session never seen before carries whichever side has one."""
    to_iterm: dict[str, str | None] = {}
    to_headset: dict[str, str | None] = {}
    for sid, (d, i) in now.items():
        was = last.get(sid)
        if was is None:
            if d is not None:
                to_iterm[sid] = d
            elif i is not None:
                to_headset[sid] = i
        elif d != was["d"]:
            to_iterm[sid] = d
        elif i != was["i"]:
            to_headset[sid] = i
    return to_iterm, to_headset


def pull(now: Now, to_headset: dict[str, str | None]) -> dict[str, str | None]:
    """Moves the headset's groups to match iTerm's; each moved session's group as `space.json`
    holds it right after."""
    after: dict[str, str | None] = {}
    for sid in [s for s, v in to_headset.items() if v is None]:
        stored.ungroup(sid)
        after[sid] = None
    for i in {i for i in to_headset.values() if i is not None}:
        movers = sorted(s for s, v in to_headset.items() if v == i)
        # Someone already in that tab group, one in a headset group first.
        stayers = sorted((d is None, s) for s, (d, ii) in now.items() if ii == i and s not in to_headset)
        if stayers:
            mate = stayers[0][1]
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


def sync() -> None:
    """One pass: read both sides, carry what moved, write down where they now agree."""
    live = [s for s in sessions.live_sessions() if s.pane is not None and s.provider == "claude"]
    panes = {s.session_id: s.pane.iterm_session_id for s in live}
    projects = {s.session_id: project.of(s.cwd) for s in live}
    poses = stored.space()["poses"]
    groups = {sid: (poses.get(f"session:{sid}") or {}).get("group") for sid in panes}
    read = iterm.call(lambda c: _tab_groups(c, panes))
    if read is None:
        return
    tabs, titles = read
    now = {sid: (groups[sid], tabs[sid]) for sid in panes if sid in tabs}  # not found is not "left"
    path = config.data_dir() / STATE
    last = _load(path)
    to_iterm, to_headset = decide(now, last)
    after = pull(now, to_headset)
    if to_iterm:
        pushed = iterm.call(lambda c: _push(c, panes, groups, to_iterm, projects))
        tabs, titles = read if pushed is None else pushed
    if to_iterm or to_headset:
        log.info("tab groups: %d into iTerm, %d into the headset", len(to_iterm), len(to_headset))
    agreed = {sid: was for sid, was in last.items() if sid in panes}  # unseen this pass: as they were
    agreed |= {sid: {"d": after.get(sid, d), "i": tabs.get(sid, i)} for sid, (d, i) in now.items()}
    if agreed != last:
        path.write_text(json.dumps(agreed, indent=2) + "\n")
    stored.name({a["d"]: titles[a["i"]] for a in agreed.values() if a["d"] and a["i"] in titles})


def _load(path: Path) -> dict[str, dict]:
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return {}


async def _tab_groups(connection: Any, panes: dict[str, str]) -> tuple[dict, dict[str, str]]:
    """Session id → the id of the tab group its pane's tab is in, for every pane iTerm has; and
    each of those tab groups' names."""
    import iterm2

    app = await iterm2.App.async_construct(connection)
    found: dict[str, str | None] = {}
    titles: dict[str, str] = {}
    for sid, pane in panes.items():
        session = app.get_session_by_id(pane)
        if session is not None and session.tab is not None:
            group = session.tab.tab_group
            found[sid] = group.group_id if group else None
            if group:
                titles[group.group_id] = group.name
    return found, titles


async def _push(connection: Any, panes: dict[str, str], groups: dict[str, str | None],
                to_iterm: dict[str, str | None], projects: dict[str, dict]) -> tuple[dict, dict[str, str]]:
    """Moves iTerm's tab groups to match the headset's, then reads them back."""
    import iterm2

    app = await iterm2.App.async_construct(connection)
    tab_of = {sid: s.tab for sid, pane in panes.items()
              if (s := app.get_session_by_id(pane)) is not None and s.tab is not None}
    for sid, d in to_iterm.items():
        tab = tab_of.get(sid)
        if d is None and tab is not None and tab.tab_group is not None:
            await tab.async_remove_from_tab_group()
    for d in {d for d in to_iterm.values() if d is not None}:
        members = sorted(s for s, g in groups.items() if g == d and s in tab_of)
        by_window: dict[str, list[str]] = {}
        for sid in members:
            by_window.setdefault(tab_of[sid].window.window_id, []).append(sid)
        for window_id, here in by_window.items():
            await _gather(app.get_window_by_id(window_id), here, tab_of, to_iterm, projects[here[0]])
    return await _tab_groups(connection, panes)


async def _gather(window: Any, here: list[str], tab_of: dict[str, Any],
                  to_iterm: dict[str, str | None], name: dict) -> None:
    """Puts the tabs of `here`, one headset group's sessions in one window, in one tab group:
    the one those that did not move are in, else the one most of them are in, else a new one."""
    import iterm2

    def group_of(sid: str) -> Any:
        return tab_of[sid].tab_group

    stayed = [g for s in here if s not in to_iterm and (g := group_of(s)) is not None]
    moved = [g for s in here if (g := group_of(s)) is not None]
    target = (Counter(stayed or moved).most_common(1) or [(None, 0)])[0][0]
    tabs = {tab_of[s].tab_id: tab_of[s] for s in here if group_of(s) != target}
    if not tabs:
        return
    if target is not None:
        for tab in tabs.values():
            await tab.async_add_to_tab_group(target)
    elif len({tab_of[s].tab_id for s in here}) > 1:
        title = name["key"].rsplit("/", 1)[-1] or "deckhand"
        await window.async_create_tab_group(title, tabs.values(), iterm2.Color.from_hex(name["color"]))
    else:
        for tab in tabs.values():
            if tab.tab_group is not None:
                await tab.async_remove_from_tab_group()
