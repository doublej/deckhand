"""The words utt is told to listen for in every clip, layered the way CLAUDE.md files are.

A hint is not a swap: utt lets one displace text that is already nearly it and starts with the
same letter. That is still a word on the phone changed into another — "Sonnet" came back as
"socket" because "socket" was on this list — so the list is the person's to read and prune,
from the phone, rather than a constant in the code.

**One list for every session, then one per folder, appended going down.** A session working in
`~/dev/web/shop` hears the global words, then `~`'s, `~/dev`'s, `~/dev/web`'s and `shop`'s own,
in that order — the words a project is full of belong to that project, the way its CLAUDE.md
does. Kept here keyed by path, like a folder's settings, rather than as files in the folders:
the phone writes them, and a session on another machine has folders this Mac cannot open.
`transcribe.hints_for` adds the session's own name and folder on top, per clip.

Written whole and read whole, like `aliases.py`. No file means the global list it was seeded with.
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
    """The global list, the one every session hears."""
    return _read()["hints"]


def save(sent: object) -> list[str]:
    """Replace the global list, and hand back exactly what was written."""
    return save_folder("", sent)


def layers(cwd: str) -> list[dict]:
    """Every list a session in `cwd` hears, outermost first: the global one under the path "",
    then each folder from the home folder down to `cwd` itself, empty ones included so the phone
    can start one. "/" and "/Users" are never a layer."""
    doc = _read()
    here = Path(cwd)
    chain = [*(p for p in reversed(here.parents) if len(p.parts) > 2), here]
    return [{"path": "", "hints": doc["hints"]},
            *({"path": str(p), "hints": doc["folders"].get(str(p), [])} for p in chain)]


def for_folder(cwd: str) -> list[str]:
    """The layers as one list, each word once, the outer spelling kept."""
    return _kept([word for layer in layers(cwd) for word in layer["hints"]])


def save_folder(folder: str, sent: object) -> list[str]:
    """Replace one folder's own words ("" is the global list); an emptied folder is forgotten."""
    doc, kept = _read(), _kept(sent)
    if not folder:
        doc["hints"] = kept
    elif kept:
        doc["folders"][str(Path(folder))] = kept
    else:
        doc["folders"].pop(str(Path(folder)), None)
    path().write_text(json.dumps(doc, indent=2))
    return kept


def _read() -> dict:
    """The stored document. Unreadable is the seeded list, so a broken file cannot stop a clip."""
    try:
        saved = json.loads(path().read_text())
    except FileNotFoundError:
        saved = {"hints": SEEDED}
    except (OSError, json.JSONDecodeError) as broken:
        log.warning("hints.json is unreadable, so the seeded list is used: %s", broken)
        saved = {"hints": SEEDED}
    saved = saved if isinstance(saved, dict) else {"hints": saved}
    folders = saved.get("folders") if isinstance(saved.get("folders"), dict) else {}
    return {"hints": _kept(saved.get("hints")),
            "folders": {str(key): _kept(words) for key, words in folders.items() if _kept(words)}}


def _kept(sent: object) -> list[str]:
    """One line each, no blanks, one row per word whatever its case — first spelling wins."""
    words: dict[str, str] = {}
    for word in sent if isinstance(sent, (list, tuple)) else []:
        flat = " ".join(str(word).split())
        if flat:
            words.setdefault(flat.casefold(), flat)
    return list(words.values())
