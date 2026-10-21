"""What is said with the panel pulled over a session's page carries that session to the model."""

from deckhand_daemon.manager import agent, talk


def test_the_viewed_session_reaches_the_model_and_not_the_panel(claude_home):
    agent.clear()
    entry = agent.ask("summarise this one", "abc123", "deckhand")
    queued = agent._queue[-1]
    agent.clear()
    # The panel draws the person's own words; the model reads which session "this one" is.
    assert entry["text"] == "summarise this one"
    assert "deckhand (id abc123)" in queued
    assert queued.endswith("summarise this one")


def test_nothing_is_added_from_the_rail(claude_home):
    talk.clear()
    agent.ask("what is running")
    queued = agent._queue[-1]
    agent.clear()
    assert queued == "what is running"
