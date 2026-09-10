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
import sys
import time
from pathlib import Path

LOOK = 2.0


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
    said = parse.parse_args()

    path = Path(said.dir).expanduser().resolve() / ".deckhand" / "artifacts"
    path = path / f"{said.slug}.answer.json"
    until = time.monotonic() + said.wait
    while True:
        value, found = readAnswer(path)
        if found:
            print(json.dumps(value, ensure_ascii=False, indent=2))
            return 0
        left = until - time.monotonic()
        if left <= 0:
            print(f"{said.slug} has not been answered yet ({path})", file=sys.stderr)
            return 1
        time.sleep(min(LOOK, left))


if __name__ == "__main__":
    sys.exit(main())
