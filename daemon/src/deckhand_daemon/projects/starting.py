"""Open a terminal in a project's folder and start Claude Code in it.

Every other route in this daemon speaks to a session that already exists. This is the one that
makes one, and it is the same three steps a person does by hand: a new iTerm window, `cd` into the
folder, run `claude`.

Three things are worth knowing about how it is done.

**A window, never a tab.** `it2 tab new` reports success and creates a real session — and that
session's shell never reads a thing typed into it. Measured: the pane comes back from
`it2 session list --json` with a tty and a live zsh on it, `it2 session run` exits 0, and the pane
holds nothing but blank lines a minute later. A tab is created relative to iTerm's *current*
window, and a daemon has no window of its own to be current in. `it2 window new` has no such
ambiguity and works first time.

**The window id is the handle, not a diff of the session list.** `it2 window new` prints
`Created new window: pty-…`, and every session in `it2 session list --json` carries the
`window_id` it sits in, so the new session is looked up rather than guessed at. Diffing the list
either side of the call also works, and is wrong the moment somebody opens a tab by hand at the
same instant.

**Bare `claude` opens the session dashboard, not a session.** Measured on 2.1.266: it draws the
"describe a task for a new session" launcher, writes no `~/.claude/sessions/<pid>.json`, and so
never appears on the phone at all. `--name` is what starts an interactive session outright, and it
is not in `claude --help` — the flag was read off the running processes on this Mac, every one of
which uses it.

**The rest of the line is the person's, and it was asked rather than assumed.** Nobody is at the
Mac to answer a permission prompt, so a session started from a phone without
`--dangerously-skip-permissions` stalls on its first tool use — which is a decision about
authority, not a default to help oneself to. JJ chose this line on a slip
(`.deckhand/artifacts/launch-line.html`): the same one every session on this Mac already runs.

**A name is a key, so it has to be free.** Favourites, the hidden set and a terminal's filter
chain are all filed under a session's *name*, so a second session called `deckhand` would silently
share the first one's star and its chain. The project's name is taken when it is free and
numbered when it is not.

**A folder Claude Code has never been trusted in stops at a prompt nobody can answer.** The
first run in a new folder asks "is this a project you created or one you trust?", and until
somebody presses a key at the Mac no session record is written — so from the phone it looks
exactly like a session that failed to start. That prompt is a real safety decision about what
Claude Code may read and execute, and answering it on somebody's behalf from another room is
precisely what it exists to prevent. So this reads the answer Claude Code already has and refuses
before opening anything, which also means no window is left stranded at a question.

**Starting is not the same as being startable.** `claude` writes its `~/.claude/sessions/<pid>.json`
a second or two after the shell runs it, and until that file exists the session does not exist as
far as the rest of Deckhand is concerned. So this waits for it and hands back the real session,
which is what lets the phone go straight into the conversation rather than back to a list and a
guess about which row is new.

Everything here goes through `it2`, which is iTerm's Python API — the one this Mac has already
approved. Driving iTerm with AppleScript instead works just as well from a terminal and would
need its own Automation grant under launchd, with nobody there to click it.
"""

from __future__ import annotations

import json
import re
import shlex
import subprocess
import time
from pathlib import Path

from ..log import log
from ..sessions import Session, live_sessions, sessions_dir

IT2_TIMEOUT = 15
# What Claude Code costs between the shell running it and its session record landing. Measured at
# two to four seconds on this Mac; the ceiling is for a cold start with a slow profile behind it.
SETTLE = 40.0
POLL = 0.5
# How long iTerm takes to have a shell in a window it has just made. Well under a second here.
OPENING = 6.0
# Everything after the name. `--dangerously-skip-permissions` is here because a phone-started
# session has nobody to approve its first tool use; `--chrome` because that is how this Mac runs.
FLAGS = ("--dangerously-skip-permissions", "--chrome")
WINDOW_ID = re.compile(r"(pty-[0-9A-Fa-f-]+)")


def trusted() -> set[str]:
    """Every folder Claude Code has been told to trust, out of its own `~/.claude.json`.

    Read rather than remembered: it is a large file a person changes by answering a dialog, and
    the whole of it is one parse behind the same minute-long cache the project list already has.
    """
    record = sessions_dir().parent.with_suffix(".json")  # ~/.claude -> ~/.claude.json
    try:
        projects = json.loads(record.read_text()).get("projects", {})
    except (OSError, json.JSONDecodeError, AttributeError):
        return set()
    if not isinstance(projects, dict):
        return set()
    return {path for path, entry in projects.items()
            if isinstance(entry, dict) and entry.get("hasTrustDialogAccepted")}


def start(cwd: str) -> tuple[Session | None, str | None]:
    """Start a session in `cwd`. Returns (the session, None) or (None, why not)."""
    folder = Path(cwd)
    if not folder.is_dir():
        return None, f"{cwd} is not a folder on this Mac"
    if cwd not in trusted():
        return None, (f"Claude Code has not been trusted in {folder.name} yet — it has to be "
                      f"started there once on the Mac and the trust question answered")
    opened = _run(["it2", "window", "new"])
    if opened is None:
        return None, "iTerm would not open a window — its Python API has to be on"
    found = WINDOW_ID.search(opened)
    if found is None:
        return None, f"iTerm opened a window but did not say which: {opened.strip()[:80]}"
    pane = _pane_in(found.group(1))
    if pane is None:
        return None, "iTerm opened a window with no session in it"
    running = live_sessions(iterm_only=False)
    known = {s.session_id for s in running}
    launch = " ".join(["claude", "--name", shlex.quote(_free_name(folder.name, running)), *FLAGS])
    if not _it2("session", "run", "-s", pane, f"cd {shlex.quote(str(folder))} && {launch}"):
        return None, "opened a window but iTerm would not run claude in it"
    log.info("started claude in %s", folder)
    return _settled(folder, known)


def _free_name(wanted: str, running: list[Session]) -> str:
    """The project's name, or the first numbered one nothing is using.

    Not cosmetic: this app files a star, a hidden row and a filter chain under the name, so two
    live sessions sharing one would share all three.
    """
    taken = {s.name for s in running}
    if wanted not in taken:
        return wanted
    return next(f"{wanted}-{n}" for n in range(2, 100) if f"{wanted}-{n}" not in taken)


def _pane_in(window: str) -> str | None:
    """The session sitting in that window. Polled, because the window exists a moment before
    anything is in it."""
    deadline = time.monotonic() + OPENING
    while time.monotonic() < deadline:
        listing = _run(["it2", "session", "list", "--json"])
        if listing is not None:
            try:
                panes = json.loads(listing)
            except json.JSONDecodeError:
                panes = []
            for pane in panes:
                if pane.get("window_id") == window and pane.get("id"):
                    return str(pane["id"])
        time.sleep(0.3)
    return None


def _settled(folder: Path, known: set[str]) -> tuple[Session | None, str | None]:
    """Wait for the new session to write its own record, and hand back the session itself.

    Matched on the folder as Claude Code resolves it: the dev tree carries a symlink or two, and
    a path that came out of a catalogue is not always spelled the way a shell reports it back.
    """
    wanted = folder.resolve()
    deadline = time.monotonic() + SETTLE
    while time.monotonic() < deadline:
        time.sleep(POLL)
        for session in live_sessions(iterm_only=False):
            if session.session_id in known or not session.cwd:
                continue
            if Path(session.cwd).resolve() == wanted:
                log.info("%s came up in %s", session.name, folder)
                return session, None
    return None, f"claude was started in {folder.name} but has not reported itself yet"


def _it2(*args: str) -> bool:
    return _run(["it2", *args]) is not None


def _run(command: list[str]) -> str | None:
    """The command's output, or None and a line in the log. Never raises: iTerm being absent is
    a thing the phone should be told about, not an exception out of a request."""
    try:
        done = subprocess.run(
            command, capture_output=True, text=True, timeout=IT2_TIMEOUT, check=False
        )
    except (OSError, subprocess.SubprocessError) as error:
        log.warning("%s failed: %s", " ".join(command[:3]), error)
        return None
    if done.returncode != 0:
        log.warning("%s exited %d: %s", " ".join(command[:3]), done.returncode,
                    done.stderr.strip()[:120])
        return None
    return done.stdout
