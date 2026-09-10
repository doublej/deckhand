"""The two calls the phone makes, and the one an agent makes for itself."""

from __future__ import annotations

from deckhand_daemon.settings import wants

SHOP = "/Users/jj/dev/web/shop"


def test_the_document_goes_out_and_comes_back(client, token):
    head = {"x-deckhand-token": token}
    assert client.get("/settings", headers=head).json()["finished"] is True
    sent = {"finished": False, "projects": {SHOP: {"chase": False}}}
    written = client.put("/settings", json=sent, headers=head).json()
    assert written["finished"] is False
    assert written["projects"][SHOP]["chase"] is False
    assert client.get("/settings", headers=head).json()["finished"] is False


def test_one_folder_is_resolved_by_the_mac_and_not_by_the_phone(client, token):
    """The same question the daemon asks itself before every card. Two answers to one question
    is how they come apart."""
    head = {"x-deckhand-token": token}
    client.put("/settings", json={"slips": True, "projects": {SHOP: {"slips": False}}}, headers=head)
    answered = client.get("/settings/project", params={"path": SHOP}, headers=head).json()
    assert answered["wants"]["slips"] is False
    assert answered["wants"]["finished"] is True


def test_settings_need_the_token(client):
    assert client.get("/settings").status_code == 401


def test_an_agent_asking_for_attention_says_whether_it_got_it(client, token, monkeypatch):
    head = {"x-deckhand-token": token}
    sid = "aaaa1111-2222-3333-4444-555566667777"
    seen: list[str] = []
    monkeypatch.setattr("deckhand_daemon.push.called",
                        lambda session, line: seen.append(line) or None)
    assert client.post(f"/sessions/{sid}/notify", json={"line": "  the build   is red "},
                       headers=head).json() == {"pushed": True}
    # Whitespace collapsed: it lands on a Lock Screen, where a newline is a card that reads wrong.
    assert seen == ["the build is red"]
    # Nothing to say is a refusal, not a blank card.
    assert client.post(f"/sessions/{sid}/notify", json={"line": "   "},
                       headers=head).status_code == 400


def test_a_folder_set_quiet_says_so_rather_than_swallowing_it(client, token, monkeypatch):
    """An agent that thinks it has your attention and has not is worse than one that knows."""
    head = {"x-deckhand-token": token}
    sid = "aaaa1111-2222-3333-4444-555566667777"
    monkeypatch.setattr("deckhand_daemon.push.called", lambda session, line: "set not to be")
    answered = client.post(f"/sessions/{sid}/notify", json={"line": "hi"}, headers=head).json()
    assert answered == {"pushed": False, "why": "set not to be"}


def test_a_folder_can_refuse_to_be_interrupted(claude_home):
    """The switch itself, under the route: `called` is the one trigger a session raises for
    itself, so it is the one a folder may refuse outright."""
    from deckhand_daemon import push, sessions
    wants.save({"called": False})
    session = next(s for s in sessions.live_sessions(iterm_only=False) if s.cwd == SHOP)
    assert push.called(session, "look at me") == "this folder is set not to be interrupted"
