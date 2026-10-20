"""The words utt is told to listen for in every clip, and the only list of them.

A hint is not a swap: utt lets one displace text that is already nearly it and starts with the
same letter. That is still a word on the phone changed into another — "Sonnet" came back as
"socket" because "socket" was on this list — so the list is the person's to read and prune,
from the phone, rather than a constant in the code. `transcribe.hints_for` adds the session's
own name and folder to it per clip; those come from what the person named, not from here.

Written whole and read whole, like `aliases.py`. No file means the list it was seeded with.
"""

from __future__ import annotations

import json
from pathlib import Path

from ..config import data_dir
from ..log import log

SEEDED = (
    "deckhand", "utt", "launchd", "onenv", "XcodeGen", "SwiftLint", "SwiftUI", "FastAPI",
    "iTerm", "TUI", "cogwheel", "JSONL", "daemon", "transcript", "Claude",
)


def path() -> Path:
    return data_dir() / "hints.json"


def load() -> list[str]:
    """Every word on the list. Unreadable is the seeded list, so a broken file cannot stop a clip."""
    try:
        saved = json.loads(path().read_text())
    except FileNotFoundError:
        return list(SEEDED)
    except (OSError, json.JSONDecodeError) as broken:
        log.warning("hints.json is unreadable, so the seeded list is used: %s", broken)
        return list(SEEDED)
    return _kept(saved.get("hints") if isinstance(saved, dict) else saved)


def save(sent: object) -> list[str]:
    """Replace the list, and hand back exactly what was written."""
    kept = _kept(sent)
    path().write_text(json.dumps({"hints": kept}, indent=2))
    return kept


def _kept(sent: object) -> list[str]:
    """One line each, no blanks, one row per word whatever its case — first spelling wins."""
    words: dict[str, str] = {}
    for word in sent if isinstance(sent, (list, tuple)) else []:
        flat = " ".join(str(word).split())
        if flat:
            words.setdefault(flat.casefold(), flat)
    return list(words.values())
