import asyncio

import claude_agent_sdk
import pytest
from claude_agent_sdk import ClaudeSDKError, ResultMessage

from deckhand_daemon import summarize as summarize_module
from deckhand_daemon import tasks
from deckhand_daemon.summarize import summarize

ACTIVITY = "Read app.py, edited two handlers, ran pytest and it passed."
run = asyncio.run


@pytest.fixture(autouse=True)
def own_data_dir(tmp_path, monkeypatch):
    summarize_module._spent.clear()
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path / "data"))


def fake_result(text: str) -> ResultMessage:
    return ResultMessage(
        subtype="success",
        duration_ms=10,
        duration_api_ms=8,
        is_error=False,
        num_turns=1,
        session_id="s1",
        result=text,
    )


def answering(text: str, calls: list[str]):
    """Stands in for the SDK's own async-generator `query`, recording every run."""

    async def fake_query(*, prompt, options, **kwargs):
        calls.append(prompt)
        yield fake_result(text)

    return fake_query


def test_empty_activity_never_reaches_the_model(monkeypatch):
    calls: list[str] = []
    monkeypatch.setattr(claude_agent_sdk, "query", answering("unused", calls))
    assert run(summarize("s1", "   \n  ")) == (None, None)
    assert calls == []


def test_a_normal_run_returns_what_the_model_wrote(monkeypatch):
    calls: list[str] = []
    monkeypatch.setattr(claude_agent_sdk, "query", answering("Edited two handlers.", calls))
    assert run(summarize("s1", ACTIVITY)) == ("Edited two handlers.", None)
    # The transcript, and the list it is read against: the model cannot avoid adding what is
    # already there if it has never been shown what is already there.
    assert ACTIVITY in calls[0]
    assert "THE LIST SO FAR" in calls[0]


def test_asking_twice_runs_twice_because_deciding_is_not_this_module_s_job(monkeypatch):
    """This writes a briefing when told to. Whether one is owed is `briefings._due`.

    It used to hold a two-minute cache of its own, which meant a session that had done nothing
    still bought a run every two minutes. The decision moved to the one place that can see the
    transcript's mtime, and this became the plain thing it says it is.
    """
    calls: list[str] = []
    monkeypatch.setattr(claude_agent_sdk, "query", answering("Edited two handlers.", calls))
    first = run(summarize("s1", ACTIVITY))
    second = run(summarize("s1", ACTIVITY))
    assert first == second
    assert len(calls) == 2


def test_a_failing_sdk_becomes_a_message_not_a_crash(monkeypatch):
    async def exploding_query(*, prompt, options, **kwargs):
        raise ClaudeSDKError("claude binary not found")
        yield  # pragma: no cover — keeps this an async generator

    monkeypatch.setattr(claude_agent_sdk, "query", exploding_query)
    summary, error = run(summarize("s1", ACTIVITY))
    assert summary is None
    assert "claude binary not found" in error


def test_the_list_is_not_in_the_answer_and_does_not_reach_the_briefing(monkeypatch):
    """The list is changed by tools while the model reads, so the prose is only prose."""
    calls: list[str] = []
    monkeypatch.setattr(claude_agent_sdk, "query", answering("Rewrote the importer.", calls))
    tasks.add("s1", "the files tab")

    briefing, error = run(summarize("s1", ACTIVITY))

    assert (briefing, error) == ("Rewrote the importer.", None)
    assert [t["text"] for t in tasks.load("s1")] == ["the files tab"]
    assert "t1 [ ] the files tab" in calls[0]


def test_the_tools_the_model_gets_are_the_three_that_manage_the_list():
    assert tasks.TOOLS == (
        "mcp__tasks__add_task",
        "mcp__tasks__set_task_state",
        "mcp__tasks__drop_task",
    )


def test_the_headline_is_the_first_line_of_the_briefing():
    assert summarize_module.headline("Waiting: which database first\n\nRewrote it.") == (
        "Waiting: which database first"
    )
    assert summarize_module.headline(None) is None
