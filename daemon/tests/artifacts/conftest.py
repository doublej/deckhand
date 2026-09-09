"""A live session working somewhere a test may write.

Artifacts live in the project rather than under Deckhand's own state, so a test that touches them
has to move the session's cwd out of `claude_home`'s fixed `/Users/jj/dev/web/shop` and into a
temporary folder. Here rather than in the shared conftest because nothing else needs it.
"""

import json

import pytest

from deckhand_daemon import sessions

SID = "aaaa1111-2222-3333-4444-555566667777"


@pytest.fixture
def project(claude_home, tmp_path):
    """The folder the session works in, empty: no `.deckhand` in it until something makes one."""
    cwd = tmp_path / "project"
    cwd.mkdir()
    record = claude_home / "sessions" / "4242.json"
    record.write_text(json.dumps(json.loads(record.read_text()) | {"cwd": str(cwd)}))
    return cwd


@pytest.fixture
def session(project):
    """That session as the daemon sees it, through the same listing the endpoints use."""
    return next(s for s in sessions.live_sessions() if s.session_id == SID)


@pytest.fixture
def asking(project):
    """One page already in the folder, the way an agent writes one: `Write` and nothing else."""
    spot = project / ".deckhand" / "artifacts"
    spot.mkdir(parents=True)
    page = spot / "which-branch.html"
    page.write_text("<title>Which branch?</title><p>develop or main</p>")
    return page
