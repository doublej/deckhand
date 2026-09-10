"""The manager's conversation: one file the daemon owns and the phone only ever reads.

The phone cannot hold a socket open to this Mac and the Mac cannot push a sentence to a phone
that is asleep, so the conversation is not a stream — it is a file with a cursor. Everything the
manager does appends a numbered entry, the phone asks for everything after the last id it saw,
and a phone that was in a pocket for an hour catches up in one call. That is the same shape
`briefings` settled on for the same reason, and it is why nothing here is lost to a restart.

Four kinds of entry, because the panel has four things to draw:

- **person** — what was said into the panel, typed or spoken.
- **manager** — what came back. Appended per text block as the run streams, so the panel fills
  in while the model is still working rather than all at once at the end.
- **act** — one tool the manager ran, in a line. Written by the tool itself, so it says what
  actually happened rather than what was asked for.
- **command** — something for the phone to do. The phone obeys the ones newer than the cursor it
  held when it opened, which is what stops a relaunch replaying yesterday's navigation.
- **note** — the daemon speaking for itself: an error, or a conversation that had to start over.

The SDK session id lives in this file beside the entries on purpose. It is what `resume` needs,
and keeping it anywhere else means a daemon restart quietly starts a second conversation while
the panel goes on showing the first one's history.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

from ..config import data_dir
from ..log import log

#: What a role may be. Anything else is a bug on this side, not something to draw.
ROLES = ("person", "manager", "act", "command", "note")
#: A ceiling on the file. The panel decides how much of it to show; this only stops a Mac left
#: running for a month growing one conversation without bound.
MAX_KEPT = 400


def path() -> Path:
    folder = data_dir() / "manager"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / "conversation.json"


def read() -> dict:
    """The whole book. A file that is not there is a manager nobody has spoken to yet."""
    try:
        book = json.loads(path().read_text())
    except FileNotFoundError:
        return _empty()
    except (OSError, json.JSONDecodeError) as error:
        log.warning("the manager's conversation is unreadable, starting a new one: %s", error)
        return _empty()
    if not isinstance(book, dict) or not isinstance(book.get("entries"), list):
        return _empty()
    book.setdefault("next", len(book["entries"]) + 1)
    book.setdefault("sdk", "")
    return book


def entries(since: int = 0) -> list[dict]:
    """Everything after the id the phone last saw. `since=0` is the whole conversation."""
    return [entry for entry in read()["entries"] if entry["id"] > since]


def newest() -> int:
    """The id of the last entry, or 0. What a phone opening the panel starts its cursor at."""
    kept = read()["entries"]
    return kept[-1]["id"] if kept else 0


def say(role: str, text: str, **extra: object) -> dict:
    """Append one entry and hand it back with the id it was given.

    Empty text is dropped rather than stored: a model that streams a bare whitespace block would
    otherwise put a blank card on the panel, and a blank card reads as something that failed.
    """
    if role not in ROLES:
        raise ValueError(f"{role!r} is not a role the panel can draw")
    if not text.strip() and not extra:
        return {}
    book = read()
    entry = {"id": book["next"], "role": role, "text": text.strip(), "said_at": time.time(), **extra}
    book["entries"].append(entry)
    book["next"] += 1
    _trim(book)
    _write(book)
    return entry


def resumes() -> str:
    """The SDK session this conversation is, or empty on the first thing ever said to it."""
    return str(read().get("sdk") or "")


def resumes_at(session_id: str) -> None:
    """Remember the SDK session, so the next thing said carries everything before it."""
    book = read()
    if book.get("sdk") == session_id:
        return
    book["sdk"] = session_id
    _write(book)


def clear() -> dict:
    """Start over: the entries go and so does the SDK session behind them.

    Both together, always. Dropping the entries and keeping the resume id would leave a panel
    that looks empty talking to a model that remembers everything, which is the one state
    nobody could reason about.
    """
    _write(_empty())
    return read()


def _empty() -> dict:
    return {"next": 1, "sdk": "", "entries": []}


def _trim(book: dict) -> None:
    while len(book["entries"]) > MAX_KEPT:
        book["entries"].pop(0)


def _write(book: dict) -> None:
    try:
        path().write_text(json.dumps(book, indent=2) + "\n")
    except OSError as error:
        log.warning("could not write the manager's conversation: %s", error)
