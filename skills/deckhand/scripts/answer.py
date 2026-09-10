#!/usr/bin/env python3
"""Wait for a slip to be answered, then print the answer.

The common shape is ask, wait, carry on, and without this it is a polling loop every session
invents from scratch. The daemon writes `<slug>.answer.json` beside the page the moment the
person responds, so this watches for that file and prints its `value` — the JSON exactly as the
page responded with it.

    answer.py which-branch                # look once; exit 1 if nobody has answered
    answer.py which-branch --wait 300     # block for five minutes

The wait is bounded by whatever runs this: a Bash tool call has its own timeout (two minutes by
default, ten at most), so `--wait 300` needs that call given at least as long. Waiting is not the
only way — the daemon also messages the session when an answer lands, so a session that has
stopped is woken rather than having to sit here.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

LOOK = 2.0


def whereAnswer(base: Path, session: str, slug: str) -> list[Path]:
    """The answer file, in each scope the daemon reads — this session's own first, then the folder.

    Both, because a session can be handed a slip it did not write: one written flat belongs to the
    folder and every session working there answers the same page. Same order the daemon resolves
    in, so what this prints is what the phone answered.
    """
    spots = [base / session, base] if session else [base]
    return [spot / f"{slug}.answer.json" for spot in spots]


def readAnswer(path: Path) -> tuple[object, bool]:
    """`(value, found)`. Not found covers absent, unreadable and half-written alike.

    The daemon writes the file in one go but not atomically, so a read can land mid-write. Half a
    file is "not answered yet" and never an error — the next look gets the whole of it. `found` is
    a flag of its own because `false`, `0`, `""` and `[]` are all real answers.
    """
    try:
        return json.loads(path.read_text())["value"], True
    except (OSError, KeyError, json.JSONDecodeError):
        return None, False


def main() -> int:
    parse = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parse.add_argument("slug", help="the slip's id — what slip.py printed")
    parse.add_argument("--wait", type=float, default=0.0, metavar="SECONDS",
                       help="how long to block (default: look once)")
    parse.add_argument("--dir", default=".", metavar="DIR",
                       help="the session's own folder (default: here)")
    parse.add_argument("--session", default=os.environ.get("CLAUDE_CODE_SESSION_ID", ""),
                       metavar="ID",
                       help="whose slip this is (default: $CLAUDE_CODE_SESSION_ID). A slip "
                            "written flat, belonging to the folder, is looked for either way")
    said = parse.parse_args()

    base = Path(said.dir).expanduser().resolve() / ".deckhand" / "artifacts"
    paths = whereAnswer(base, said.session, said.slug)
    until = time.monotonic() + said.wait
    while True:
        for path in paths:
            value, found = readAnswer(path)
            if found:
                print(json.dumps(value, ensure_ascii=False, indent=2))
                return 0
        left = until - time.monotonic()
        if left <= 0:
            print(f"{said.slug} has not been answered yet ({paths[0]})", file=sys.stderr)
            return 1
        time.sleep(min(LOOK, left))


if __name__ == "__main__":
    sys.exit(main())
