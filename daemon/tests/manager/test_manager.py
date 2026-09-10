"""The manager: what it writes down, what it refuses, and the drift the tool list can develop."""

from fastapi.testclient import TestClient

from deckhand_daemon import prompts
from deckhand_daemon.app import app
from deckhand_daemon.manager import agent, doing, talk


def client(token):
    c = TestClient(app)
    c.headers["x-deckhand-token"] = token
    return c


def test_every_tool_is_described_in_the_prompt_file(claude_home):
    """A tool with no description in `prompts/manager.md` raises a KeyError when the server is
    built — which happens on the first thing anyone says, on the daemon, with nobody watching."""
    described = set(prompts.load("manager").settings["tools"])
    named = {name.removeprefix("mcp__deckhand__") for name in doing.TOOLS}
    assert named == described


def test_the_conversation_is_a_cursor_not_a_stream(claude_home):
    talk.clear()
    first = talk.say("person", "what is running")
    second = talk.say("manager", "three sessions")
    assert [e["id"] for e in talk.entries()] == [first["id"], second["id"]]
    assert talk.entries(since=first["id"]) == [second]
    assert talk.newest() == second["id"]


def test_clearing_drops_the_thread_as_well_as_the_words(claude_home):
    talk.say("person", "hello")
    talk.resumes_at("a-session-id")
    assert talk.resumes() == "a-session-id"
    talk.clear()
    # Both together, always: entries without the thread is a panel that looks empty talking to
    # a model that remembers everything.
    assert talk.entries() == []
    assert talk.resumes() == ""


def test_an_empty_thing_said_is_not_written_down(claude_home):
    talk.clear()
    assert talk.say("person", "   ") == {}
    assert talk.entries() == []


def test_the_panel_is_only_told_verbs_it_has(claude_home):
    talk.clear()
    refused = doing.on_phone("delete_everything", "")["content"][0]["text"]
    assert "open_session" in refused
    assert talk.entries() == []


def test_a_pane_the_app_does_not_have_is_refused_before_it_is_written(claude_home):
    talk.clear()
    assert "is not a pane" in doing.on_phone("open_pane", "nope")["content"][0]["text"]
    assert talk.entries() == []
    doing.on_phone("open_pane", "slips")
    written = talk.entries()[-1]
    assert written["role"] == "command"
    assert written["command"] == {"action": "open_pane", "target": "slips"}


def test_a_switch_this_mac_does_not_have_is_named_rather_than_written(claude_home):
    answer = doing.switch("", "route", "keyboard")["content"][0]["text"]
    # The route is the authority choice and it is the person's. It is deliberately not a switch
    # the manager can set, and the refusal says which ones are.
    assert "not a switch" in answer
    assert "chase" in answer


def test_switches_take_the_words_a_model_actually_writes(claude_home):
    assert doing._value("chase", "yes") is True
    assert doing._value("chase", "OFF") is False
    assert doing._value("chase", "maybe") is None
    assert doing._value("summary_model", " claude-sonnet-5 ") == "claude-sonnet-5"


def test_naming_a_session_that_is_not_running_says_which_are(claude_home):
    answer = doing.speak("nobody", "hello")["content"][0]["text"]
    assert "warm-okapi" in answer and "cold-otter" in answer


def test_saying_something_answers_at_once_and_queues_the_run(claude_home, token, monkeypatch):
    talk.clear()
    monkeypatch.setattr(agent, "_queue", [])
    body = client(token).post("/manager/say", json={"text": "how is deckhand doing"}).json()
    assert body["entry"]["role"] == "person"
    assert body["working"] is True
    assert agent._queue == ["how is deckhand doing"]


def test_reading_the_panel_answers_after_the_cursor(claude_home, token):
    talk.clear()
    one = talk.say("person", "first")
    talk.say("manager", "second")
    body = client(token).get(f"/manager?since={one['id']}").json()
    assert [e["text"] for e in body["entries"]] == ["second"]
    assert body["newest"] == one["id"] + 1
    assert body["working"] is False


def test_the_panel_needs_the_token_like_everything_else(claude_home):
    assert TestClient(app).get("/manager").status_code == 401
