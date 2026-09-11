"""Which machines exist, read from atlas's registry rather than from a list of our own.

Atlas owns this question. `shared/hosts.json` in its repo holds every machine on the network
with an ssh alias, a scan root, an os and a role, and atlas has frozen six of those field names
(`id`, `label`, `ssh`, `root`, `os`, `role`) precisely because this file reads them — a rename
there breaks a repo that will not fail to compile over there.

**The file, not `/api/hosts`.** Two reasons, and atlas's own docs name the file as the surface
anyway (atlas-picker, in Rust, reads it the same way). First, atlas imports the registry as an
ESM module, so its daemon serves the copy it started with and a registry edit is invisible over
HTTP until a reload. Second, deckhand has to keep answering the phone when atlas is not running.

**Nothing else of atlas's is read.** Not `~/dev/.atlas-cache-<id>.json`, which atlas has ruled
internal: the main cache carries a `shapeVersion` so a consumer can detect a change and bail,
and the per-host fragment has no such field, so a change in it would be silent here.
"""

from __future__ import annotations

import json
import os
import socket
from dataclasses import dataclass
from pathlib import Path

from ..log import log

# Atlas's own tree. `~/dev` is the real path; `~/Documents/development` is a symlink that must
# never be used, because two paths to one repo double every cache under it.
REGISTRY = Path.home() / "dev" / "multi-stack" / "project-atlas" / "shared" / "hosts.json"


def registry_path() -> Path:
    return Path(os.environ.get("DECKHAND_ATLAS_REGISTRY", REGISTRY))


@dataclass(frozen=True, slots=True)
class Machine:
    """One machine on the network. The six fields atlas has promised to keep, and nothing else —
    `node`, `agent` and `skipGit` belong to atlas's scan agent and are never read here."""

    id: str
    label: str
    ssh: str | None  # the alias, never an IP: every host here is DHCP and has already drifted
    root: str
    os: str  # darwin | linux | win32 — picks the liveness and socket path on a hand
    role: str

    @property
    def is_primary(self) -> bool:
        """This Mac: the one machine reached without ssh, where the daemon itself runs."""
        return self.ssh is None


def _fallback() -> Machine:
    """What a machine list looks like with no atlas installed: this Mac, alone, as it was before
    any of this. A missing registry is not an error — it is a network of one."""
    name = socket.gethostname().split(".")[0]
    return Machine(id=name, label=name, ssh=None, root=str(Path.home()), os="darwin", role="primary")


def machines() -> list[Machine]:
    """Every machine atlas knows, primary first. Falls back to this Mac alone.

    Read fresh each call rather than cached: the file is a few hundred bytes, and a stale machine
    list is the kind of wrong that shows up as a session that cannot be reached.
    """
    path = registry_path()
    try:
        raw = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        # Atlas not installed, or mid-write. Either way the honest answer is "just this Mac".
        log.warning("no atlas registry at %s (%s)", path, error.__class__.__name__)
        return [_fallback()]
    found = [_machine(entry) for entry in raw.get("hosts", []) if entry.get("id")]
    if not any(m.is_primary for m in found):
        # A registry with no local machine cannot describe the machine we are running on.
        log.warning("atlas registry names no primary; falling back to this Mac")
        return [_fallback()]
    return sorted(found, key=lambda m: (not m.is_primary, m.id))


def _machine(entry: dict) -> Machine:
    ident = entry["id"]
    return Machine(
        id=ident,
        # Display copy, hand-editable in atlas and validated by nobody. Blank falls back to the
        # id here so the phone is never handed an empty row; length is the render site's problem.
        label=(entry.get("label") or "").strip() or ident,
        ssh=entry.get("ssh"),
        root=entry.get("root", ""),
        os=entry.get("os", ""),
        role=entry.get("role", ""),
    )


def primary() -> Machine:
    """The machine the daemon is running on."""
    return next((m for m in machines() if m.is_primary), _fallback())


def here() -> str:
    """This machine's id — what every session listed by this daemon is stamped with."""
    return primary().id
