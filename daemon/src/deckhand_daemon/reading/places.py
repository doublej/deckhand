"""The folders a session's work lands in without anybody connecting them.

Renders, screenshots and reports pile up in a handful of places by habit: the orchestrator's
`.orchestrate/`, a project's `tmp/` or `output/`, and Claude Code's own per-session scratchpad,
`/tmp/claude-<uid>/<project>/<session>/scratchpad`, whose `<project>` is the transcript's own
folder name. The files tab lists these the way it lists a connected folder, and serves from them
for the same reason: they are this session's work, in its own project or its own scratch space.

Only names that exist are returned, each resolved, so a symlink cannot point a place elsewhere.
"""

from __future__ import annotations

import os
from pathlib import Path

from .transcripts import transcript_path

NAMES = (".orchestrate", "tmp", "temp", ".tmp", "output", "renders", "screenshots")
#: Where Claude Code keeps a session's scratchpad, under `claude-<uid>/`.
SCRATCH = Path("/tmp")


def of(session_id: str, cwd: str) -> list[str]:
    """Every work folder this session has, in the project first, then its scratchpad."""
    found = [Path(cwd) / name for name in NAMES]
    if transcript := transcript_path(session_id):
        found.append(SCRATCH / f"claude-{os.getuid()}" / transcript.parent.name / session_id / "scratchpad")
    return [str(path.resolve()) for path in found if path.is_dir()]
