#!/usr/bin/env python3
"""Wait for a slip to be answered, then print the answer and whether the person's phone signed it.

The common shape is ask, wait, carry on, and without this it is a polling loop every session
invents from scratch. The daemon writes `<slug>.answer.json` beside the page the moment the
person responds, so this watches for that file and prints

    {"value": <the JSON exactly as answered>, "verified": true|false,
     "device": "<phone name>"|null, "fingerprint": "<16 hex>"|null}

    answer.py which-branch                # look once; exit 1 if nobody has answered
    answer.py which-branch --wait 300     # block for five minutes

**`verified` is re-checked here, never read off the file.** The file sits in the session's own
folder and anything can write one, `"verified": true` included. A decision's answer is true only
when the proof kept in the file is a valid signature, by a key a paired phone filed with the
daemon, over this very page as it is now and over this very value. A hand-written file, a
non-decision slip, or a page rewritten since, all read `false`. Checking needs `cryptography`; a
Python without it reads `false` rather than guessing.

The wait is bounded by whatever runs this: a Bash tool call has its own timeout (two minutes by
default, ten at most), so `--wait 300` needs that call given at least as long. Waiting is not the
only way — the daemon types a decision's answer into the session as the person's next message,
so the usual shape is to ask, end the turn, and read the answer when it arrives.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import sys
import time
from pathlib import Path

LOOK = 2.0
DECISION = b'<meta name="deckhand-decision"'


def whereAnswer(base: Path, session: str, slug: str) -> list[Path]:
    """The answer file, in each scope the daemon reads — this session's own first, then the folder.

    Both, because a session can be handed a slip it did not write: one written flat belongs to the
    folder and every session working there answers the same page. Same order the daemon resolves
    in, so what this prints is what the phone answered.
    """
    spots = [base / session, base] if session else [base]
    return [spot / f"{slug}.answer.json" for spot in spots]


def readAnswer(path: Path) -> tuple[dict, bool]:
    """`(record, found)`. Not found covers absent, unreadable and half-written alike.

    The daemon writes a decision's answer atomically and any other in one go, so a read can still
    land mid-write on an old daemon. Half a file is "not answered yet" and never an error — the
    next look gets the whole of it. `found` is a flag of its own because `false`, `0`, `""` and `[]`
    are all real answers.
    """
    try:
        record = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return {}, False
    found = isinstance(record, dict) and "value" in record
    return (record, True) if found else ({}, False)


def dataDir() -> Path:
    """The daemon's state folder, by its own rule (`config.data_dir`)."""
    if override := os.environ.get("DECKHAND_DATA_DIR"):
        return Path(override)
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "Deckhand"
    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / "deckhand"


def proven(record: dict, page: Path) -> bool:
    """Whether the kept proof is a paired phone's signature over this page and this value."""
    try:
        from cryptography.exceptions import InvalidSignature
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import ec
    except ImportError:
        return False
    proof = record.get("proof")
    if not isinstance(proof, dict) or not record.get("fingerprint"):
        return False
    try:
        rows = json.loads((dataDir() / "devices.json").read_text()).get("devices", [])
        key = next(row["key"] for row in rows
                   if row.get("key") and row.get("fingerprint") == record["fingerprint"])
        signed = base64.b64decode(proof["payload"], validate=True)
        public = ec.EllipticCurvePublicKey.from_encoded_point(
            ec.SECP256R1(), base64.b64decode(key, validate=True))
        public.verify(base64.b64decode(proof["signature"], validate=True), signed,
                      ec.ECDSA(hashes.SHA256()))
        said = json.loads(signed)
        current = hashlib.sha256(page.read_bytes()).hexdigest()
    except (OSError, KeyError, TypeError, StopIteration, ValueError, InvalidSignature):
        return False
    return (isinstance(said, dict) and said.get("hash") == current == record.get("hash")
            and said.get("artifact") == page.name.removesuffix(".html")
            and said.get("value") == record["value"])


def reading(record: dict, page: Path) -> dict:
    """What this prints: the value, and who proved it — null unless the proof holds."""
    held = proven(record, page)
    return {"value": record["value"], "verified": held,
            "device": record.get("device") if held else None,
            "fingerprint": record.get("fingerprint") if held else None}


def answeredDecision(page: Path) -> dict | None:
    """The reading of this page's answer when the page is a decision that has one, else None.

    `slip.py` asks this before rewriting a page: an answered decision is never asked again under
    the same key, because rewriting it would delete the person's answer.
    """
    try:
        with page.open("rb") as file:
            if DECISION not in file.read(8192):
                return None
    except OSError:
        return None
    record, found = readAnswer(page.with_name(page.name.removesuffix(".html") + ".answer.json"))
    return reading(record, page) if found else None


def main() -> int:
    parse = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parse.add_argument("slug", help="the slip's id — what slip.py printed")
    parse.add_argument("--wait", type=float, default=0.0, metavar="SECONDS",
                       help="how long to block (default: look once)")
    parse.add_argument("--dir", default=".", metavar="DIR",
                       help="the session's own folder (default: here)")
    parse.add_argument("--session", default=os.environ.get("CLAUDE_CODE_SESSION_ID")
                       or os.environ.get("OPENCODE_SESSION_ID", ""),
                       metavar="ID",
                       help="whose slip this is (default: $CLAUDE_CODE_SESSION_ID, else OpenCode's "
                            "$OPENCODE_SESSION_ID). A slip "
                            "written flat, belonging to the folder, is looked for either way")
    said = parse.parse_args()

    base = Path(said.dir).expanduser().resolve() / ".deckhand" / "artifacts"
    paths = whereAnswer(base, said.session, said.slug)
    until = time.monotonic() + said.wait
    while True:
        for path in paths:
            record, found = readAnswer(path)
            if found:
                page = path.with_name(f"{said.slug}.html")
                print(json.dumps(reading(record, page), ensure_ascii=False, indent=2))
                return 0
        left = until - time.monotonic()
        if left <= 0:
            print(f"{said.slug} has not been answered yet ({paths[0]})", file=sys.stderr)
            return 1
        time.sleep(min(LOOK, left))


if __name__ == "__main__":
    sys.exit(main())
