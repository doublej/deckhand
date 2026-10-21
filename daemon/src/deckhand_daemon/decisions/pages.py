"""What makes a slip a decision, read off its own `<head>`, and the hash that pins an answer to it.

`slip.py` writes four `<meta>` tags into a confirm, pick or text page: `deckhand-decision` (the
kind), `deckhand-choices` (an HTML-escaped JSON array), `deckhand-action` (what a yes allows, in
one line) and `deckhand-expires` (unix seconds). A page without a known kind is not a decision,
whatever else it carries, and every field here is null on its row.

**The hash is of the whole file's bytes**, not of the parts that look like the question. Any
rewrite — a reworded question, a new choice, a changed action line, a note — makes a new hash, so
a card drawn off the old page cannot answer the new one. Narrower would mean deciding which edits
"do not count", and that is the judgement a forged approval hides in.

**A row re-checks its answer rather than trusting the file's own `verified`.** The answer sits in
the session's folder, where an agent can write one by hand; `verified` on the phone is true only
when the stored proof verifies against a paired device's key and was made for this very page.
"""

from __future__ import annotations

import hashlib
import html
import json
import re
import time
from pathlib import Path

from . import proofs

KINDS = ("confirm", "pick", "text")
#: The metas live in the head, and a page carrying a `data:` picture runs to megabytes.
PEEK = 8192
META = re.compile(rb"""<meta\s+name="deckhand-([a-z]+)"\s+content=(["'])(.*?)\2\s*/?>""",
                  re.IGNORECASE | re.DOTALL)
#: The keys every listing row carries, null for a page that is not a decision.
FIELDS = ("decision", "choices", "action", "expires", "hash", "verified", "answered_by", "expired")


def hashed(page: Path) -> str:
    """sha256 hex of the page file's bytes. Any rewrite makes a new one."""
    return hashlib.sha256(page.read_bytes()).hexdigest()


def declared(page: Path) -> dict | None:
    """`{decision, choices, action, expires}` for a decision page, None for any other page.

    A choices meta that does not parse is an empty list rather than a refusal, and an expiry that
    does not parse is 0 — lapsed, which is the safe way for a broken decision to read.
    """
    try:
        with page.open("rb") as file:
            head = file.read(PEEK)
    except OSError:
        return None
    metas = {name.decode().lower(): html.unescape(value.decode("utf-8", "replace"))
             for name, _, value in META.findall(head)}
    if metas.get("decision") not in KINDS:
        return None
    try:
        choices = json.loads(metas.get("choices", "[]"))
    except json.JSONDecodeError:
        choices = []
    try:
        expires = float(metas.get("expires", "0"))
    except ValueError:
        expires = 0.0
    return {"decision": metas["decision"],
            "choices": [str(c) for c in choices] if isinstance(choices, list) else [],
            "action": metas.get("action", ""), "expires": expires}


def kept(answer: Path | None) -> dict | None:
    """The answer file as written, or None — absent, unreadable and half-written alike."""
    if answer is None or not answer.is_file():
        return None
    try:
        found = json.loads(answer.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    return found if isinstance(found, dict) else None


def fields(page: Path, answer: Path | None) -> dict:
    """What a listing row adds for this page: every key in `FIELDS`, null when not a decision."""
    found = declared(page)
    if found is None:
        return dict.fromkeys(FIELDS)
    current = hashed(page)
    written = kept(answer)
    held = written is not None and proofs.holds(written, current, page.stem)
    return found | {
        "hash": current,
        "verified": held,
        "answered_by": written.get("device") if held and written else None,
        "expired": written is None and time.time() > found["expires"],
    }
