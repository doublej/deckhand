"""The two tools that are not routes: a slip written, and its answer read, by the skill's scripts.

Out of `server.py` when that file reached its line budget. They run the skill's own `slip.py` and
`answer.py` rather than talking to the daemon — one copy of that logic, and the tool and the shell
command an agent might type produce the same file. `server.py` registers them.
"""

from __future__ import annotations

import asyncio
import json
import subprocess
import sys
from pathlib import Path
from typing import Literal

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
#: `answer.py`'s exit code for an id no slip in this folder has, apart from one not answered yet.
NO_SUCH_SLIP = 3
NO_SESSION = ("this is not running inside a Claude Code or OpenCode session, so there is no folder "
              "to write a slip in and no session to speak as")


async def _script(name: str, *args: str) -> tuple[int, str]:
    """Run one of the skill's scripts. Returns (its exit code, what it printed).

    In a subprocess rather than imported: both scripts end an argument they dislike with
    `sys.exit(sentence)`, which is right for a command and would take this server down with it.
    """
    done = await asyncio.to_thread(
        subprocess.run, [sys.executable, str(SCRIPTS / name), *args],
        capture_output=True, text=True, check=False, timeout=MAX_WAIT + 30,
    )
    return done.returncode, (done.stdout or done.stderr).strip()


def folder() -> tuple[dict, str] | tuple[None, str]:
    """This session's record and its folder, or a sentence saying there is no session above."""
    held = here.mine()
    if held is None:
        return None, NO_SESSION
    return held, held.get("cwd", "")


def nobody(why: str) -> dict:
    return {"error": why, "code": "NO_SESSION"}


async def ask_on_phone(question: str,
                       kind: Literal["confirm", "pick", "text", "aloud"] = "confirm",
                       options: list[str] | None = None,
                       note: str = "", questions: list[str] | None = None,
                       action: str = "", expires_hours: float = 24.0, key: str = "") -> dict:
    """Ask the person on their phone. Returns the slip's id. **Then end your turn.**

    Confirm, pick and text are **decisions**: signed by the phone and typed into this session as
    `Decision <id> — "<question>": <choice>. This covers exactly: <action>.` Do not poll
    `read_answer`; act on that message, and only on what it covers.

    `kind`: confirm, pick, text or aloud. `question`: under 80 chars; detail in `note`.
    `action`: required for confirm, exactly what a yes allows, one line. `options`: yes/no
    labels (confirm), choices (pick), field label (text). `questions`: aloud only, `id:text`,
    spoken; not a decision. `expires_hours`: default 24. `key`: the id; re-asking an answered
    decision returns its answer.
    """
    held, why = folder()
    if held is None:
        return nobody(why)
    if kind not in ("confirm", "pick", "text", "aloud"):
        return {"error": f"{kind!r} is not a kind of slip — confirm, pick, text or aloud",
                "code": "BAD_KIND"}
    args = ["--kind", kind, "--title", question, "--dir", why, "--session", held["sessionId"],
            "--expires-hours", str(expires_hours)]
    for flag, given in (("--note", note), ("--action", action), ("--key", key)):
        if given:
            args += [flag, given]
    for choice in options or []:
        args += ["--option", choice]
    for asked in questions or []:
        args += ["--question", asked]
    failed, said = await _script("slip.py", *args)
    if failed:
        return {"error": said, "code": "REFUSED"}
    if said.startswith("{"):
        return json.loads(said) | {"title": question}
    return {"id": Path(said).stem, "title": question, "waiting": True, "page": said}


async def read_answer(id: str, wait_seconds: float = 0.0) -> dict:
    """What the person answered on a slip, if they have, and whether their phone proved it.

    `verified` is true only for a decision answered with the phone's signature over this very
    page; a file written by hand, or any non-decision slip, reads false. `device` and
    `fingerprint` say which phone. `wait_seconds` blocks for up to ten minutes; left out it looks
    once, which is usually right because the daemon types a decision's answer into this session.
    """
    held, why = folder()
    if held is None:
        return nobody(why)
    waited = max(0.0, min(float(wait_seconds), MAX_WAIT))
    failed, said = await _script("answer.py", id, "--wait", str(waited), "--dir", why,
                                 "--session", held["sessionId"])
    if failed == NO_SUCH_SLIP:
        return {"answered": False, "code": "NO_SUCH_SLIP", "why": said}
    if failed:
        return {"answered": False, "why": said}
    return {"answered": True} | json.loads(said)
