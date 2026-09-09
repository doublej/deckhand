"""The chain the person saved: which steps run, in what order, with what settings.

One file, `filters.json`, and the array order *is* the order they run in. A filter may appear
more than once with different settings, so nothing here is keyed by name — a step is a position
in a list, not an entry in a table.

A missing or unreadable file loads as an empty chain. Every store in this daemon does that, and
here it matters more than most: a half-written settings file must not be able to stop someone
speaking to a session.
"""

from __future__ import annotations

import json
from pathlib import Path

from ..config import data_dir
from ..log import log


def path() -> Path:
    return data_dir() / "filters.json"


def load() -> list[dict]:
    """The saved steps, normalised, so nothing downstream has to be defensive about them."""
    try:
        saved = json.loads(path().read_text())
    except FileNotFoundError:
        return []
    except (OSError, json.JSONDecodeError) as broken:
        log.warning("filters.json is unreadable, so nothing is filtered: %s", broken)
        return []
    steps = saved.get("steps") if isinstance(saved, dict) else None
    if not isinstance(steps, list):
        log.warning("filters.json has no list of steps, so nothing is filtered")
        return []
    return [_step(given) for given in steps if isinstance(given, dict) and given.get("filter")]


def save(steps: list[dict]) -> list[dict]:
    """Replace the chain, and hand back exactly what was written."""
    kept = [_step(given) for given in steps if isinstance(given, dict) and given.get("filter")]
    path().write_text(json.dumps({"steps": kept}, indent=2))
    return kept


def _step(given: dict) -> dict:
    """One step with all three keys present: a step missing `on` is on, not broken."""
    settings = given.get("settings")
    return {
        "filter": str(given["filter"]),
        "on": bool(given.get("on", True)),
        "settings": settings if isinstance(settings, dict) else {},
    }
