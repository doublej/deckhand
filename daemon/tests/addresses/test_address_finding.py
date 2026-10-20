"""What counts as an address in a transcript, and how one server's spellings become one row."""

from __future__ import annotations

import json

from deckhand_daemon.addresses import finding

SESSION = "aaaa1111-2222-3333-4444-555566667777"


def test_one_server_written_three_ways_is_one_origin():
    found = finding.found_in("open http://127.0.0.1:5173/admin, or localhost:5173, bound 0.0.0.0:5173")
    assert {origin for origin, _, _ in found} == {"http://localhost:5173"}
    assert ("http://localhost:5173", "url", "/admin") in found


def test_code_that_ends_like_a_domain_is_not_one():
    text = "self.page = Deckhand.app; expect(x).to.be; os.path.join; v1.2.3.4; mask 255.255.255.0"
    assert finding.found_in(text) == []


def test_bare_ips_and_domains_are_found_with_their_ports():
    found = finding.found_in("the NAS at 192.168.1.20 and staging at shop.example.nl:8443 — mail jj@gmail.com")
    assert ("http://192.168.1.20", "ip", "") in found
    assert ("http://shop.example.nl:8443", "domain", "") in found
    assert all("gmail" not in origin for origin, _, _ in found)


def test_placeholders_networks_and_json_escapes_stay_out():
    text = r'{"x": "see https://example.com/a and 192.0.2.1 in 10.0.0.0/8, then http://localhost:4180/health\n"}'
    assert finding.found_in(text) == [("http://localhost:4180", "url", "/health")]


def test_said_beats_printed_and_subagents_are_read(claude_home):
    def row(kind, content, at):
        return json.dumps({"type": kind, "timestamp": at, "message": {"content": content}})

    folder = claude_home / "projects" / "-Users-jj-dev"
    (folder / f"{SESSION}.jsonl").write_text("\n".join([
        row("user", [{"type": "tool_result", "content": "docs at https://docs.python.org/3/"}], "2026-10-20T10:00:02Z"),
        row("assistant", [{"type": "text", "text": "server is up on http://localhost:5173"}], "2026-10-20T10:00:01Z"),
        json.dumps({"type": "attachment", "content": "https://claude.ai/everywhere"}),
    ]) + "\n")
    agents = folder / SESSION / "subagents"
    agents.mkdir(parents=True)
    (agents / "agent-a1.jsonl").write_text(
        row("assistant", [{"type": "text", "text": "deployed to https://shop.jurrejan.com/"}], "2026-10-20T10:00:03Z") + "\n")

    rows = finding.mentioned(SESSION)
    assert [r.origin for r in rows] == ["https://shop.jurrejan.com", "http://localhost:5173",
                                        "https://docs.python.org"]
    assert rows[0].in_agents and rows[0].said
    assert not rows[2].said
