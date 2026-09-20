"""Starting a session where there is no iTerm: tmux, on Ubuntu and on Fractal.

`starting.py` is `it2` from end to end — a window, then the pane id out of that window, then a
line run in that pane — and there is no fallback in it to switch off. So this is the second
backend that observation always implied (`docs/network.md`, *Left out*), and it is deliberately
the smallest one that can exist: tmux makes a detached window, runs `claude` in it, and
everything after that is `starting`'s own waiting, unchanged and shared.

**Two facts, measured on 2026-09-13 rather than assumed.**

- On Fractal `claude.exe` resolves inside a tmux session on its own, to
  `C:\\Users\\jurre\\.local\\bin\\claude.exe`.
- On Ubuntu it does not. `command -v claude` inside a detached tmux session finds nothing,
  because a detached session or window reads no login profile — the same hole `fleet/link.py`
  already patches
  for `uv`, and patched here the same way. Without it the tmux session is created, exits
  instantly, and the failure reads as "claude was started but has not reported itself yet":
  a timeout forty seconds later describing the wrong thing entirely.

**No pane, and that is not a gap.** A hand has no iTerm, so `Session.pane` stays None and every
screen reads that as "cannot be typed into" — which is what a remote session already is. The
keyboard route refuses here for the reason it always refused, and nothing about the authority
invariant is relaxed to let this exist.
"""

from __future__ import annotations

import shlex
import shutil
import subprocess
import sys
from pathlib import Path

from ..log import log
from ..sessions import Session, live_sessions
from .starting import free_name, settled, trusted

TMUX_TIMEOUT = 15
#: Everything after the name, and deliberately *not* `starting.FLAGS`. That tuple carries
#: `--chrome` as well, which is a statement about how this Mac runs rather than about how a
#: session should be started; a headless Ubuntu server is not that Mac. What does carry over is
#: `--dangerously-skip-permissions`, because the reason for it is unchanged — nobody is at that
#: machine either to answer the first permission prompt — and it was JJ's decision, not a default
#: helped oneself to.
HAND_FLAGS = ("--dangerously-skip-permissions",)


def start(cwd: str, model: str = "") -> tuple[Session | None, str | None]:
    """Start a session in `cwd` on this machine. Returns (the session, None) or (None, why not).

    `model` is the hub's answer for this folder, passed across rather than looked up: what the
    person set is on the Mac, and a hand keeps no settings of its own to disagree with it.
    """
    folder = Path(cwd)
    if not folder.is_dir():
        return None, f"{cwd} is not a folder on this machine"
    if cwd not in trusted():
        return None, (f"Claude Code has not been trusted in {folder.name} yet — it has to be "
                      f"started there once on that machine and the trust question answered")
    running = live_sessions(iterm_only=False)
    known = {s.session_id for s in running}
    name = free_name(folder.name, running)
    if not _new_session(name, folder, model):
        return None, "tmux would not start a session there"
    log.info("started claude in %s under tmux", folder)
    return settled(folder, known)


def _new_session(name: str, folder: Path, model: str) -> bool:
    """A window in the session the person actually attaches to where there is one, a detached
    session of its own where there is not. Detached either way, because nobody is watching: the
    hand has to outlive this request, and that is what makes tmux the supervisor and not us.

    A hand used to be a session of its own always, and that was the bug: bare `tmux` starting the
    server meant the server was started from `~/.tmux.conf`, so a byobu login arriving second
    joined it and silently lost byobu's status bar and keybinds entirely. Measured on mbp-ubuntu
    on 2026-09-20 — whoever wins the race to start the server decides whether the person has a
    byobu at all. A window in their own session cannot win that race.
    """
    handle = _handle(name)
    try:
        target = _person_session()
        if target is None:
            command = [_tmux(), "new-session", "-d", "-s", handle, "-c", str(folder)]
        else:
            command = [_tmux(), "new-window", "-d", "-t", f"{target}:", "-n", handle, "-c", str(folder)]
        done = subprocess.run(
            [*command, _launch(name, model)],
            capture_output=True, text=True, timeout=TMUX_TIMEOUT, check=False
        )
        if done.returncode == 0 and target is not None:
            # Or claude renames the tab off `deckhand-…` the moment it starts, and the prefix
            # `_handle` exists for stops meaning anything.
            subprocess.run(
                [_tmux(), "set-window-option", "-t", f"{target}:{handle}", "automatic-rename", "off"],
                capture_output=True, text=True, timeout=TMUX_TIMEOUT, check=False
            )
    except (OSError, subprocess.SubprocessError) as error:
        log.warning("tmux failed: %s", error)
        return False
    if done.returncode != 0:
        log.warning("tmux exited %d: %s", done.returncode, done.stderr.strip()[:160])
        return False
    return True


def _tmux() -> str:
    """byobu's wrapper where the machine has one, which is `tmux -u -2 -f <byobu profile>`.

    `-f` is read only by a *starting* server, so this is what decides the config when deckhand is
    the one that starts it. Never `-L` or `-S` and never `TMUX_TMPDIR`: byobu is on the default
    socket, and a hand on any other socket is a hand the person cannot see.
    """
    return shutil.which("byobu-tmux") or "tmux"


def _person_session() -> str | None:
    """The session to hang a hand off: one a person is attached to, else the most recently used.

    Hands are excluded by their own prefix, so on a machine nobody is logged into each one stays
    a session of its own rather than piling into the first one's and dying with it. No server at
    all exits non-zero here, which is the same answer — and then the old behaviour, exactly.
    """
    listed = subprocess.run(
        [_tmux(), "list-sessions", "-F", "#{session_attached} #{session_activity} #{session_name}"],
        capture_output=True, text=True, timeout=TMUX_TIMEOUT, check=False
    )
    if listed.returncode != 0:
        return None
    return _pick(listed.stdout)


def _pick(listing: str) -> str | None:
    """The newest attached session in that listing, or the newest of any, ignoring hands."""
    rows = [line.split(" ", 2) for line in listing.splitlines() if line.count(" ") >= 2]
    theirs = [r for r in rows if not r[2].startswith("deckhand-")]
    theirs.sort(key=lambda r: (int(r[0]), int(r[1])), reverse=True)
    return theirs[0][2] if theirs else None


def _handle(name: str) -> str:
    """What tmux calls the window. Prefixed, so a person looking at their tab bar can see which
    of them arrived from a phone and which they opened themselves."""
    return f"deckhand-{name}"


def _launch(name: str, model: str) -> str:
    """The line tmux runs. One string, because the two shells quote nothing alike.

    ponytail: Windows quoting is the plain `"…"` form rather than a real argv builder. Every dev
    root on that machine is space-free by convention (`C:\\dev`), and a folder that breaks that
    is the day this needs `subprocess.list2cmdline`.
    """
    chosen = ["--model", model] if model else []
    if sys.platform == "win32":
        return " ".join(["claude.exe", "--name", f'"{name}"', *chosen, *HAND_FLAGS])
    launch = " ".join(["claude", "--name", shlex.quote(name), *chosen, *HAND_FLAGS])
    # `~/.local/bin` on PATH explicitly: a detached tmux session reads no login profile, so
    # without this Ubuntu's `claude` is not on it. See the module docstring.
    return f'PATH="$HOME/.local/bin:$PATH" {launch}'
