"""The folders a person has connected to a project, so its file listing reaches past the transcript.

A session that renders into a temp folder names the folder once and none of the frames, so the
listing `files.py` reads off the transcript never sees them. Connecting that folder from the phone
is the person's explicit choice, and the choice is the permission: `/file` serves what lies inside
a folder connected to the session's own project, once every symlink is resolved — nothing more.

Keyed by the project's folder (a session's `cwd`), like `wants.py`. Written whole and read whole,
like `hints.py`. No file means no folder is connected anywhere.
"""

from __future__ import annotations

import json
from pathlib import Path

from ..config import data_dir
from ..log import log


def path() -> Path:
    return data_dir() / "folders.json"


def load(project: str) -> list[str]:
    """Every folder connected to this project, as it resolves now."""
    return _kept(_projects().get(project))


def save(project: str, sent: object) -> list[str]:
    """Replace this project's folders, and hand back exactly what was kept."""
    kept = _kept(sent)
    projects = _projects()
    if kept:
        projects[project] = kept
    else:
        projects.pop(project, None)
    path().write_text(json.dumps({"projects": projects}, indent=2))
    return kept


def settled(raw: str) -> str | None:
    """The folder `raw` names, `~` expanded and symlinks resolved — or None for one that may not
    be connected: a relative path has nothing the person could see to be relative to, and the
    disk's root or the home folder itself would turn a window onto one job into the whole Mac."""
    folder = Path(raw.strip() or ".").expanduser()
    if not folder.is_absolute():
        return None
    folder = folder.resolve()
    if folder in (Path("/"), Path.home().resolve()):
        return None
    return str(folder)


def _projects() -> dict:
    """Every project's folders. Unreadable is none, so a broken file cannot stop a listing."""
    try:
        saved = json.loads(path().read_text())
    except FileNotFoundError:
        return {}
    except (OSError, json.JSONDecodeError) as broken:
        log.warning("folders.json is unreadable, so no folder is connected: %s", broken)
        return {}
    projects = saved.get("projects") if isinstance(saved, dict) else None
    return projects if isinstance(projects, dict) else {}


def _kept(sent: object) -> list[str]:
    """Each folder once, in the order given, dropping what `settled` refuses."""
    found = (settled(str(raw)) for raw in (sent if isinstance(sent, (list, tuple)) else []))
    return list(dict.fromkeys(f for f in found if f))
