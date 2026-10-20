"""Which addresses the phone shows first, and the one reason each gets."""

from __future__ import annotations

from datetime import datetime

from deckhand_daemon.addresses import atlas, ranking
from deckhand_daemon.addresses.checking import Check
from deckhand_daemon.addresses.finding import Found

NOW = datetime.fromisoformat("2026-10-20T12:00:00Z").timestamp()
HOME = atlas.Known("shop", "/dev/web/shop", 4109, {"shop.nl", "web-shop.atlas.local.jurrejan.com"},
                   local="https://web-shop.atlas.local.jurrejan.com")
EINK = atlas.Known("eink", "/dev/web/eink", 4110, {"web-eink.atlas.local.jurrejan.com"})


def _ranked(*found):
    rows = ranking.rank(list(found), {f.origin: Check("loads", "public") for f in found},
                        [HOME, EINK], HOME, NOW)
    return [(r["origin"], r["tier"], r["why"]) for r in rows]


def test_the_project_and_what_was_just_shared_lead_and_old_tool_output_trails():
    assert _ranked(
        Found("https://docs.python.org", "url", last_at="2026-10-20T11:59:00Z"),  # printed only
        Found("https://shared.dev", "url", last_at="2026-10-20T11:00:00Z", shared_at="2026-10-20T11:00:00Z"),
        Found("https://staging.shop.nl", "url", last_at="2026-10-19T09:00:00Z"),
        Found("http://localhost:4109", "ip", last_at="2026-10-19T09:00:00Z", used_at="2026-10-19T09:00:00Z"),
        Found("https://api.other.io", "url", last_at="2026-10-20T11:30:00Z", used_at="2026-10-20T11:30:00Z"),
        Found("https://old.dev", "url", last_at="2026-10-19T08:00:00Z", shared_at="2026-10-19T08:00:00Z"),
    ) == [
        ("https://shared.dev", "important", "Shared in the conversation"),
        ("https://staging.shop.nl", "important", "Staging"),
        ("http://localhost:4109", "important", "This project's dev server"),
        ("https://api.other.io", "recent", "Used by the session"),
        ("https://old.dev", "recent", "Shared earlier"),
        ("https://docs.python.org", "rest", "Seen in tool output"),
    ]


def test_another_projects_atlas_address_matters_only_when_the_session_said_it():
    printed = Found("https://web-eink.atlas.local.jurrejan.com", "url", last_at="2026-10-20T11:59:00Z")
    used = Found("https://web-eink.atlas.local.jurrejan.com", "url", last_at="2026-10-20T11:59:00Z",
                 used_at="2026-10-19T08:00:00Z")
    assert _ranked(printed)[0][1] == "rest"
    assert _ranked(used)[0][1:] == ("important", "Atlas · eink")


def test_the_session_belongs_to_the_nearest_project_above_it():
    assert ranking.project_of("/dev/web/shop/src", [HOME, EINK]) is HOME
    assert ranking.project_of("/dev/web/shopping", [HOME, EINK]) is None
