import asyncio

import claude_agent_sdk
import pytest
from claude_agent_sdk import ClaudeSDKError, ResultMessage

from deckhand_daemon import summarize as summarize_module
from deckhand_daemon.summarize import summarize

ACTIVITY = "Read app.py, edited two handlers, ran pytest and it passed."
run = asyncio.run


@pytest.fixture(autouse=True)
def empty_cache():
    summarize_module._cache.clear()


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
    assert calls == [ACTIVITY]


def test_the_same_activity_is_summarised_once(monkeypatch):
    calls: list[str] = []
    monkeypatch.setattr(claude_agent_sdk, "query", answering("Edited two handlers.", calls))
    first = run(summarize("s1", ACTIVITY))
    second = run(summarize("s1", ACTIVITY))
    assert first == second
    assert len(calls) == 1


def test_a_failing_sdk_becomes_a_message_not_a_crash(monkeypatch):
    async def exploding_query(*, prompt, options, **kwargs):
        raise ClaudeSDKError("claude binary not found")
        yield  # pragma: no cover — keeps this an async generator

    monkeypatch.setattr(claude_agent_sdk, "query", exploding_query)
    summary, error = run(summarize("s1", ACTIVITY))
    assert summary is None
    assert "claude binary not found" in error
