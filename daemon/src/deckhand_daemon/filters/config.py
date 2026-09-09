"""The chain each terminal saved: which steps run for it, in what order, with what settings.

One file, `filters.json`, holding a chain per session **name**. The array order *is* the order
they run in, and a filter may appear in one chain more than once with different settings, so
nothing inside a chain is keyed by name — a step is a position in a list, not an entry in a table.

**The name is the key, not the id and not the cwd.** A session id is new every time Claude Code
restarts in that pane, so an id-keyed chain would be gone by morning; a cwd is shared by every
session working in one project, and what was asked for is per terminal. A name is what survives a
restart, which is what makes it the identity of the terminal rather than of the process. The phone
keys its favourites and its hidden set the same way and for the same reason. The price is that a
rename is the one thing that can lose a chain, which is why `renamed` below exists and why the
rename endpoint calls it — a chain that vanishes on `/rename` is the same bug as a lost star.

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


def load(session_name: str) -> list[dict]:
    """One terminal's chain. Empty when that terminal has never had one."""
    return _read().get(session_name, [])


def save(session_name: str, steps: list[dict]) -> list[dict]:
    """Replace one terminal's chain, and hand back exactly what was written."""
    kept = _steps(steps)
    chains = _read()
    if kept:
        chains[session_name] = kept
    else:
        # An empty chain is the absence of one rather than an entry holding nothing.
        chains.pop(session_name, None)
    _write(chains)
    return kept


def renamed(was: str, now: str) -> bool:
    """Carry a terminal's chain onto its new name. True when there was one to carry.

    The same shape as the phone's `Preferences.renamed(from:to:)`, down to overwriting whatever
    stood at the new name: the chain being moved belongs to the session that is live, and an
    entry left behind by some earlier session of that name is not worth keeping over it.
    """
    if was == now:
        return False
    chains = _read()
    moving = chains.pop(was, None)
    if moving is None:
        return False
    chains[now] = moving
    _write(chains)
    log.info("carried %s's filter chain onto %s", was, now)
    return True


def _read() -> dict[str, list[dict]]:
    """Every chain, normalised, so nothing downstream has to be defensive about any of them."""
    try:
        saved = json.loads(path().read_text())
    except FileNotFoundError:
        return {}
    except (OSError, json.JSONDecodeError) as broken:
        log.warning("filters.json is unreadable, so nothing is filtered: %s", broken)
        return {}
    if not isinstance(saved, dict):
        log.warning("filters.json is not an object, so nothing is filtered")
        return {}
    chains = saved.get("chains")
    if isinstance(chains, dict):
        return {
            str(name): _steps(steps) for name, steps in chains.items() if isinstance(steps, list)
        }
    if isinstance(saved.get("steps"), list):
        _retire(saved["steps"])
        return {}
    log.warning("filters.json holds no chains, so nothing is filtered")
    return {}


def _retire(steps: list) -> None:
    """The one Mac-wide chain there used to be, moved aside rather than carried over.

    A chain belongs to a terminal now and this one has no terminal. Copying it onto every session
    would hand out a setting nobody chose — prompt crafting among them, which buys a model run per
    prompt — and every copy would then have to be found and switched off one terminal at a time.
    Dropping it means the next dictation is unfiltered, which is obvious and harmless; the other
    way round is a bill. So it is written to the log whole and the file is kept beside the new one,
    and moving it is also what stops this being said again on every prompt.
    """
    kept = path().with_suffix(".global.json")
    log.warning(
        "filters are per terminal now, so the old Mac-wide chain is not carried over. It is kept "
        "at %s and was: %s", kept, json.dumps({"steps": steps}),
    )
    try:
        path().rename(kept)
    except OSError as trouble:
        log.warning("could not move the old chain aside: %s", trouble)


def _write(chains: dict[str, list[dict]]) -> None:
    path().write_text(json.dumps({"chains": chains}, indent=2))


def _steps(steps: list) -> list[dict]:
    return [_step(given) for given in steps if isinstance(given, dict) and given.get("filter")]


def _step(given: dict) -> dict:
    """One step with all three keys present: a step missing `on` is on, not broken."""
    settings = given.get("settings")
    return {
        "filter": str(given["filter"]),
        "on": bool(given.get("on", True)),
        "settings": settings if isinstance(settings, dict) else {},
    }
