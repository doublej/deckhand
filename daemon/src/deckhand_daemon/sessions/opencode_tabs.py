"""Which OpenCode sessions a TUI on this Mac has open: the phone's IDLE, against its OFF.

The listing shows every OpenCode session touched in the last two hours (`opencode.LIVE_FOR`).
That answers "what happened lately", not "what is still open", and on 2026-10-16 JJ asked for the
phone to tell the two apart. The service cannot say: nothing in its OpenAPI document lists its
clients or what each one shows (`POST /session/{id}/view` only marks an idle transition as seen).
The TUI can. It keeps its tabs in `<state>/opencode/<channel>/tui/tabs.json`, with one list every
TUI shows (`global`) and one per folder a TUI was started in (`cwd`). Each TUI tab there is a
session id and its title. Read off OpenCode 2.0.31.

**A TUI tab counts only while a TUI runs in its folder.** The file outlives the TUI, the way
`~/.claude/sessions/<pid>.json` outlives Claude Code, and the same kind of join settles it:
`pgrep` for the `opencode` processes that have a terminal and no subcommand, and `lsof` for the
folder each one was started in. The `global` list counts while any TUI runs.

**None, not an empty set, when this machine cannot be asked** (no `pgrep` or `lsof`, as on a
Windows hand). An empty set says every session is closed. None says nothing, and the phone draws
such a row the way it always did.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from pathlib import Path

from .. import config

#: OpenCode's subcommands (`opencode --help`, 2.0.31). A process whose first word is one of these
#: is a tool run from a shell, not a TUI. `mini` is an interface too, but it keeps no TUI tabs.
SUBCOMMANDS = frozenset({"upgrade", "update", "uninstall", "acp", "api", "debug", "auth", "mcp",
                         "plugin", "models", "stats", "mini", "run", "session", "service",
                         "reload", "pair", "serve"})
#: The flags that take a value, so the word after one of them is not the folder argument.
VALUED = frozenset({"--server", "--session", "-s", "--prompt", "--log-level", "--completions"})
#: What `ps` writes for a process with no terminal: `??` on macOS, `?` on Linux.
NO_TTY = frozenset({"??", "?", "-"})
#: What each probe waits. These run while the listing is being built, under its lock.
PROBE = 2.0

#: The sessions the person closed from Deckhand, in its own state folder.
CLOSED = "opencode-closed.json"

#: pid -> the folder that TUI keys its tabs by, or "" for an `opencode` process that is no TUI.
#: A running process does not change what it was started as, so each pid is asked once and
#: dropped when it goes.
_folders: dict[int, str] = {}
#: The tab files as last read: their (path, mtime) pairs, and folder -> session ids, with ""
#: standing for the `global` list.
_read: tuple[tuple, dict[str, set[str]]] = ((), {})


def open_sessions(state: Path) -> set[str] | None:
    """The ids a running TUI on this Mac has as a TUI tab, or None when that cannot be known.

    `state` is OpenCode's state folder, the one its service registration sits in.
    """
    folders = clients()
    if folders is None:
        return None
    if not folders:
        return set()
    tabs = _tabs(state)
    found = set(tabs.get("", ()))
    for folder in folders:
        found |= tabs.get(folder, set())
    return found


def close(session_id: str) -> None:
    """Take a session off the listing until anything touches it again.

    OpenCode 2.0.31 has no archive, its DELETE takes the conversation with it, and a TUI's tabs
    cannot be closed from outside that TUI. So closing is Deckhand's own: the history stays
    OpenCode's, and the session comes back the moment its `updated` moves past the close.
    """
    kept = closed()
    kept[session_id] = time.time() * 1000  # OpenCode's own milliseconds
    (config.data_dir() / CLOSED).write_text(json.dumps(kept))


def closed() -> dict[str, float]:
    """session id -> when the person closed it. Nothing closed yet is an empty answer."""
    try:
        return json.loads((config.data_dir() / CLOSED).read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def clients() -> set[str] | None:
    """The folders a TUI is running in on this Mac. The seam the tests replace."""
    if not (shutil.which("pgrep") and shutil.which("lsof")):
        return None
    listed = _run(["pgrep", "-x", "opencode"])
    if listed is None:
        return None
    pids = {int(word) for word in listed.split() if word.isdigit()}
    for gone in set(_folders) - pids:
        del _folders[gone]
    if new := pids - set(_folders):
        _folders.update(_ask(new))
    return {folder for pid in pids if (folder := _folders.get(pid))}


def _ask(pids: set[int]) -> dict[int, str]:
    """What each new `opencode` process is: the folder of a TUI, or "" for anything else.

    A pid this could not settle is left out, so the next listing asks again rather than taking
    a probe that timed out for a process that is no TUI.
    """
    joined = ",".join(str(pid) for pid in sorted(pids))
    described = _run(["ps", "-o", "pid=,tty=,command=", "-p", joined])
    if described is None:
        return {}
    answer: dict[int, str] = {}
    started: dict[int, str] = {}
    for line in described.splitlines():
        parts = line.split(None, 2)
        if len(parts) < 3 or not parts[0].isdigit():
            continue
        pid, tty, command = int(parts[0]), parts[1], parts[2]
        given = None if tty in NO_TTY else folder_argument(command.split()[1:])
        if given is None:
            answer[pid] = ""
        else:
            started[pid] = given
    if not started:
        return answer
    cwds = _cwds(set(started))
    for pid, given in started.items():
        if cwd := cwds.get(pid):
            answer[pid] = os.path.realpath(os.path.join(cwd, given)) if given else cwd
    return answer


def folder_argument(words: list[str]) -> str | None:
    """The folder a TUI was told to start in: "" for none, None when this is no TUI at all."""
    skip = False
    for word in words:
        if skip:
            skip = False
        elif word in VALUED:
            skip = True
        elif not word.startswith("-"):
            return None if word in SUBCOMMANDS else word
    return ""


def _cwds(pids: set[int]) -> dict[int, str]:
    """Each pid's working folder, out of `lsof -F`, which writes `p<pid>` and then `n<path>`."""
    out = _run(["lsof", "-a", "-d", "cwd", "-Fn", "-p", ",".join(str(p) for p in sorted(pids))])
    found: dict[int, str] = {}
    pid = 0
    for line in (out or "").splitlines():
        if line.startswith("p") and line[1:].isdigit():
            pid = int(line[1:])
        elif line.startswith("n") and pid:
            found[pid] = line[1:]
    return found


def _tabs(state: Path) -> dict[str, set[str]]:
    """folder -> the session ids of its TUI tabs, re-read when any tab file changes.

    Every channel's file at once (`latest` is the only one on this Mac): a TUI of another build
    keeps its own, and a session is open whichever TUI it is open in. A file that will not parse
    is caught mid-write, so the read is not kept and the next listing reads again.
    """
    global _read
    paths = sorted(state.glob("*/tui/tabs.json"))
    stamp = tuple((str(path), _mtime(path)) for path in paths)
    if stamp == _read[0]:
        return _read[1]
    found: dict[str, set[str]] = {}
    whole = True
    for path in paths:
        try:
            kept = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            whole = False
            continue
        if not isinstance(kept, dict):
            continue
        _add(found, "", kept.get("global"))
        folders = kept.get("cwd")
        for folder, group in (folders.items() if isinstance(folders, dict) else ()):
            _add(found, str(folder), group)
    if whole:
        _read = (stamp, found)
    return found


def _add(found: dict[str, set[str]], folder: str, group: object) -> None:
    tabs = group.get("tabs") if isinstance(group, dict) else None
    if not isinstance(tabs, list):
        return
    ids = {str(tab["sessionID"]) for tab in tabs if isinstance(tab, dict) and tab.get("sessionID")}
    if ids:
        found.setdefault(folder, set()).update(ids)


def _mtime(path: Path) -> float:
    try:
        return path.stat().st_mtime
    except OSError:
        return 0.0


def _run(argv: list[str]) -> str | None:
    """A probe's stdout, or None when it could not run. `pgrep` and `ps -p` exit 1 for "none
    found", which is an answer, so the exit code is not the test."""
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=PROBE, check=False).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
