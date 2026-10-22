"""Open a terminal in a project's folder and start Claude Code in it.

Every other route in this daemon speaks to a session that already exists. This is the one that
makes one, and it is the same steps a person does by hand: a new tmux window in the folder, run
`claude` in it. The window goes into the tmux session the person is attached to, so it shows up
in their own window list (`tmux.open_window`).

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

tmux needs no approval and no grant under launchd, which iTerm's Python API and AppleScript both
did.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import time
from pathlib import Path

from ..log import log
from ..sessions import Session, forget_listing, forget_panes, live_sessions, sessions_dir
from ..settings import wants

# What Claude Code costs between the shell running it and its session record landing. Measured at
# two to four seconds on this Mac; the ceiling is for a cold start with a slow profile behind it.
SETTLE = 40.0
POLL = 0.5
# Everything after the name. `--dangerously-skip-permissions` is here because a phone-started
# session has nobody to approve its first tool use; `--chrome` because that is how this Mac runs.
FLAGS = ("--dangerously-skip-permissions", "--chrome")
# The monorepo's own scratch root, `~/dev/CLAUDE.md`'s "Scratch → _sandbox". Derived from the
# home directory rather than written out: no absolute path into the dev tree belongs in a file.
SANDBOX = ("dev", "_sandbox")
# What a folder name is allowed to be made of. Everything else becomes a hyphen, and the name
# is cut to five words — the sandbox is full of `phone-finder` and `disk-space`, not sentences.
SLUG = re.compile(r"[^a-z0-9]+")
SLUG_WORDS = 5


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


def sandbox_root() -> Path:
    """Where work with no home of its own goes on this Mac."""
    return Path.home().joinpath(*SANDBOX)


def scratch_folder(name: str) -> tuple[Path | None, str | None]:
    """A folder under the sandbox for a task with no project, ready to be started in.

    The one thing in this daemon that *makes* a place rather than finding one, and the bound is
    the whole of why it is allowed: it is the sandbox or it is nothing. A name carrying a
    separator or a `..` is refused outright rather than sanitised — `../../etc` slugified is
    `etc`, which is inside the sandbox and is not what anybody asked for — and the resolved
    folder's parent is checked against the root, which holds whatever the name was.

    A folder with anything in it is somebody's scratch project and is refused by name. An empty
    one is reused: the folder is made before the terminal is opened, so a start that failed in
    tmux would otherwise have burnt the name.
    """
    wanted = (name or "").strip()
    if "/" in wanted or "\\" in wanted or ".." in wanted:
        return None, (f"{wanted!r} is not a folder name. A scratch folder is one plain name — "
                      f"no slashes, no dots leading anywhere.")
    slug = "-".join(SLUG.sub("-", wanted.lower()).strip("-").split("-")[:SLUG_WORDS])
    if not slug:
        return None, f"there is no folder name to make out of {wanted!r}"
    root = sandbox_root()
    if not root.is_dir():
        return None, f"there is no sandbox at {root} on this Mac"
    folder = (root / slug).resolve()
    if folder.parent != root.resolve():
        return None, f"{slug!r} would land outside the sandbox, so nothing was made"
    if folder.is_dir() and any(folder.iterdir()):
        return None, (f"{slug} is already a scratch folder with work in it. Pick another name, "
                      f"or start a session in it with start_session.")
    folder.mkdir(exist_ok=True)
    _trust(folder)
    return folder, None


def _trust(folder: Path) -> None:
    """Write the entry the trust dialog writes, for a folder made a moment ago.

    `start` refuses a folder Claude Code has not been trusted in, and one that did not exist a
    second ago never has been — so without this the whole of `scratch_folder` could only end in
    that refusal. What makes it honest rather than a permission answered from another room is
    that the folder is **empty**: there is nothing in it to trust, and this daemon made it.
    Measured on 2.1.270: Claude Code does not ask the trust question in a new folder at all, so
    the gate this satisfies is this daemon's own.

    Read, change one key, write back through `os.replace` — that file is a megabyte of somebody's
    whole Claude Code configuration. Read-modify-write, so a `claude` writing it in the same
    instant loses that write, as it does to itself. **`ensure_ascii=False` is not optional** and
    the default is the trap: the file is raw UTF-8, so escaping every non-ASCII character turns
    one changed key into a rewrite of all 1.4 MB. With it, exactly the bytes that were read.
    """
    if folder.parent != sandbox_root().resolve():
        return
    record = sessions_dir().parent.with_suffix(".json")  # ~/.claude -> ~/.claude.json
    try:
        document = json.loads(record.read_text())
    except (OSError, json.JSONDecodeError):
        log.warning("no ~/.claude.json to record trust for %s in", folder.name)
        return
    projects = document.setdefault("projects", {})
    if not isinstance(projects, dict):
        return
    entry = projects.get(str(folder))
    projects[str(folder)] = {**(entry if isinstance(entry, dict) else {}),
                             "hasTrustDialogAccepted": True}
    half = record.parent / f"{record.name}.deckhand"
    half.write_text(json.dumps(document, indent=2, ensure_ascii=False))
    os.replace(half, record)
    log.info("made %s and recorded it as trusted", folder)


def start(
    cwd: str, *, person_named_it: bool = False, model: str = ""
) -> tuple[Session | None, str | None]:
    """Start a session in `cwd`. Returns (the session, None) or (None, why not).

    **On this Mac the trust record is this daemon's gate and not Claude Code's**, which is the
    measurement written out under *What the trust dialog actually does* in `docs/manager.md`:
    Claude Code shows no dialog here in a folder it has never been trusted in, starts anyway, and
    files the folder as `hasTrustDialogAccepted: false`. So what this gate stands in for is
    *somebody having chosen this folder* — and `person_named_it` is that question already
    answered, by the person saying the path out loud into the manager's panel.

    **`this Mac` is load-bearing and was learnt the hard way.** The same flag on Ubuntu's hand
    stranded a tmux window on the trust dialog: same 2.1.278, same launch line, `/home/jurrejan`
    recorded exactly as `/Users/jurrejan` is here, and it asked. Whatever the difference is, it
    is not one this daemon can see from another machine — so `projects/tmux.py` keeps its check
    and this parameter does not cross the wire.

    False for every other caller, and that is deliberate: the phone's picker and a project name
    both reach a folder through a list, where the record is the only thing that says the person
    ever meant it. `docs/manager.md` under *Any folder, when the person names one* is the whole
    of the reasoning.
    """
    folder = Path(cwd)
    if not folder.is_dir():
        return None, f"{cwd} is not a folder on this Mac"
    if not person_named_it and cwd not in trusted():
        return None, (
            f"Claude Code has not been trusted in {folder.name} yet — it has to be "
            f"started there once on the Mac and the trust question answered"
        )
    from . import tmux  # tmux.py builds on this module, so not at the top

    running = live_sessions(paned_only=False)
    known = {s.session_id for s in running}
    # The model asked for this one start, else the folder's own, else Claude Code's default —
    # an absent flag and a flag saying "the default" are different things to the CLI.
    chosen = model or wants.resolved(str(folder)).session_model
    model = ["--model", chosen] if chosen else []
    name = free_name(folder.name, running)
    launch = " ".join(["claude", "--name", shlex.quote(name), *model, *FLAGS])
    if not tmux.open_window(name, folder, launch):
        return None, "tmux would not open a window there"
    log.info("started claude in %s", folder)
    return settled(folder, known)


def free_name(wanted: str, running: list[Session]) -> str:
    """The project's name, or the first numbered one nothing is using.

    Not cosmetic: this app files a star, a hidden row and a filter chain under the name, so two
    live sessions sharing one would share all three.
    """
    taken = {s.name for s in running}
    if wanted not in taken:
        return wanted
    return next(f"{wanted}-{n}" for n in range(2, 100) if f"{wanted}-{n}" not in taken)


def settled(folder: Path, known: set[str]) -> tuple[Session | None, str | None]:
    """Wait for the new session to write its own record, and hand back the session itself.

    Matched on the folder as Claude Code resolves it: the dev tree carries a symlink or two, and
    a path that came out of a catalogue is not always spelled the way a shell reports it back.
    """
    wanted = folder.resolve()
    deadline = time.monotonic() + SETTLE
    while time.monotonic() < deadline:
        time.sleep(POLL)
        # The listing is cached for a couple of seconds, and this loop is waiting for a session
        # that did not exist when the cached one was built — the one caller that has to ask
        # again rather than be told what was true a moment ago.
        forget_listing()
        for session in live_sessions(paned_only=False):
            # A Codex thread loaded in the same folder meanwhile is not the session this started.
            if session.session_id in known or not session.cwd or session.provider != "claude":
                continue
            if Path(session.cwd).resolve() == wanted:
                log.info("%s came up in %s", session.name, folder)
                return _with_pane(session), None
    return None, f"claude was started in {folder.name} but has not reported itself yet"


def _with_pane(session: Session) -> Session:
    """The same session, with its pane filled in.

    The pane map is cached for three seconds, and a window opened two seconds ago was not in it
    when it was built — so a freshly started session is reported with `pane: null`, which every
    screen reads as "cannot be typed into". True a moment later and wrong in the receipt, which
    is the half of it that gets shown.
    """
    if session.pane is not None:
        return session
    forget_panes()
    forget_listing()
    for fresh in live_sessions(paned_only=False):
        if fresh.session_id == session.session_id:
            return fresh
    return session
