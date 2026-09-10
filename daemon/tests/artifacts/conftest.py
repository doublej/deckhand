"""A live session working somewhere a test may write.

Artifacts live in the project rather than under Deckhand's own state, so a test that touches them
has to move the session's cwd out of `claude_home`'s fixed `/Users/jj/dev/web/shop` and into a
temporary folder. Here rather than in the shared conftest because nothing else needs it.
"""

import json

import pytest

from deckhand_daemon import sessions

SID = "aaaa1111-2222-3333-4444-555566667777"
# The second live session in `claude_home`, moved into the same folder. Two sessions in one repo
# is the ordinary case and the one the flat store got wrong.
OTHER_SID = "bbbb1111-2222-3333-4444-555566667777"


def _at(claude_home, pid: str, cwd) -> None:
    record = claude_home / "sessions" / f"{pid}.json"
    record.write_text(json.dumps(json.loads(record.read_text()) | {"cwd": str(cwd)}))


@pytest.fixture
def project(claude_home, tmp_path):
    """The folder the session works in, empty: no `.deckhand` in it until something makes one."""
    cwd = tmp_path / "project"
    cwd.mkdir()
    _at(claude_home, "4242", cwd)
    return cwd


@pytest.fixture
def session(project):
    """That session as the daemon sees it, through the same listing the endpoints use."""
    return next(s for s in sessions.live_sessions() if s.session_id == SID)


@pytest.fixture
def sibling(claude_home, project):
    """A second live session moved into the same folder — it must not see the first one's slips.

    It is moved here rather than in `project`, because the rest of the suite leans on the other
    live session working somewhere with no `.deckhand` folder at all.
    """
    _at(claude_home, "4243", project)
    return next(s for s in sessions.live_sessions() if s.session_id == OTHER_SID)


@pytest.fixture
def asking(project):
    """One page in the folder itself, the way an agent writes one: `Write` and nothing else.

    Flat, so it is the folder's rather than any session's — which is what every slip written
    before scopes existed is, and what the fifteen already on this Mac stayed.
    """
    spot = project / ".deckhand" / "artifacts"
    spot.mkdir(parents=True)
    page = spot / "which-branch.html"
    page.write_text("<title>Which branch?</title><p>develop or main</p>")
    return page


@pytest.fixture
def mine(project):
    """One page in the first session's own folder — where a slip written today goes."""
    spot = project / ".deckhand" / "artifacts" / SID
    spot.mkdir(parents=True)
    page = spot / "palette-pick.html"
    page.write_text("<title>Pick a palette</title><p>warm or cold</p>")
    return page
