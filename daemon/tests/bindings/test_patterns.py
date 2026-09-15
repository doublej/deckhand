"""What a pattern is and which bindings a page belongs to, with no HTTP and no disk."""

from __future__ import annotations

import pytest

from deckhand_daemon.bindings.patterns import matching, normalised

SHOP = "/Users/jj/dev/web/shop"
DOCS = "/home/jj/dev/web/docs"


def bound(pattern: str, path: str = SHOP, last_used: str | None = None) -> dict:
    return {"pattern": pattern, "path": path, "last_used": last_used}


@pytest.mark.parametrize(("sent", "kept"), [
    ("https://Example.com/", "https://example.com"),
    ("https://example.com/docs/", "https://example.com/docs"),
    ("HTTP://EXAMPLE.com:8080/Docs?q=1#top", "http://example.com:8080/Docs"),
    ("https://user:secret@a.com/x//", "https://a.com/x"),
])
def test_a_pattern_is_kept_one_way_however_it_was_spelled(sent, kept):
    assert normalised(sent) == kept


@pytest.mark.parametrize("sent", [
    "", "example.com", "https://", "ftp://example.com", "file:///etc/hosts",
    "javascript:alert(1)", "https://a.com:99999",
])
def test_anything_but_an_http_url_with_a_host_is_refused(sent):
    with pytest.raises(ValueError):
        normalised(sent)


def test_no_binding_matches_nothing():
    assert matching([], "https://a.com/x") == []


def test_one_binding_is_its_own_match():
    one = bound("https://a.com")
    assert matching([one], "https://a.com/anything") == [one]


def test_a_page_two_projects_share_answers_both_most_recently_used_first():
    older = bound("https://a.com", SHOP, "2026-09-14T10:00:00.000Z")
    newer = bound("https://a.com", DOCS, "2026-09-15T10:00:00.000Z")
    never = bound("https://a.com", "/Users/jj/dev/web/other")
    assert matching([older, never, newer], "https://a.com/") == [newer, older, never]


def test_the_longest_prefix_wins_over_the_most_recent_use():
    site = bound("https://a.com", last_used="2026-09-15T10:00:00.000Z")
    docs = bound("https://a.com/docs", DOCS)
    assert matching([site, docs], "https://a.com/docs/x") == [docs, site]


def test_a_prefix_ends_on_a_whole_path_segment():
    docs = bound("https://a.com/docs")
    assert matching([docs], "https://a.com/docs") == [docs]
    assert matching([docs], "https://a.com/docs/a?b=c") == [docs]
    assert matching([docs], "https://a.com/docsx") == []
    assert matching([docs], "https://a.com/") == []


def test_another_origin_or_port_is_another_site():
    site = bound("https://a.com")
    for url in ("http://a.com", "https://a.com:8443", "https://b.com", "https://sub.a.com"):
        assert matching([site], url) == []
    assert matching([bound("https://a.com:8443")], "https://a.com") == []


def test_the_page_is_compared_by_its_normalised_origin():
    port = bound("https://a.com:8080")
    assert matching([port], "HTTPS://A.com:8080/x?y#z") == [port]


def test_a_page_that_is_not_http_is_refused():
    with pytest.raises(ValueError):
        matching([bound("https://a.com")], "file:///etc/hosts")
