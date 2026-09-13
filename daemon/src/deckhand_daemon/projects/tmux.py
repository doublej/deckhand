"""Starting a session where there is no iTerm: tmux, on Ubuntu and on Fractal.

`starting.py` is `it2` from end to end — a window, then the pane id out of that window, then a
line run in that pane — and there is no fallback in it to switch off. So this is the second
backend that observation always implied (`docs/network.md`, *Left out*), and it is deliberately
the smallest one that can exist: tmux makes a detached session, runs `claude` in it, and
everything after that is `starting`'s own waiting, unchanged and shared.

**Two facts, measured on 2026-09-13 rather than assumed.**

- On Fractal `claude.exe` resolves inside a tmux session on its own, to
  `C:\\Users\\jurre\\.local\\bin\\claude.exe`.
- On Ubuntu it does not. `command -v claude` inside a detached tmux session finds nothing,
  because that session reads no login profile — the same hole `fleet/link.py` already patches
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
    """`tmux new-session -d`, detached, in that folder, running claude.

    Detached because there is nobody watching it: the session has to outlive this request, and
    `-d` is what makes tmux the supervisor rather than this process.
    """
    command = ["tmux", "new-session", "-d", "-s", _handle(name), "-c", str(folder), _launch(name, model)]
    try:
        done = subprocess.run(
            command, capture_output=True, text=True, timeout=TMUX_TIMEOUT, check=False
        )
    except (OSError, subprocess.SubprocessError) as error:
        log.warning("tmux failed: %s", error)
        return False
    if done.returncode != 0:
        log.warning("tmux exited %d: %s", done.returncode, done.stderr.strip()[:160])
        return False
    return True


def _handle(name: str) -> str:
    """What tmux calls the window. Prefixed, so a person looking at `tmux ls` on that machine can
    see which sessions arrived from a phone and which they started themselves."""
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
