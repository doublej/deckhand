"""The `deckhand` command: the same fifteen tools as the MCP server, and how it says no."""

import asyncio
import json
from pathlib import Path

import pytest

from deckhand_daemon.mcp import cli, refused, server, slips, tmux


def test_every_tool_is_a_command_and_every_command_a_tool():
    """The two doors stay the same size: a tool added without a command fails here."""
    tools = {t.name for t in asyncio.run(server.server.list_tools())}
    assert {c["tool"] for c in cli.COMMANDS} == tools
    assert all(callable(getattr(server, c["tool"])) for c in cli.COMMANDS)


def test_every_error_code_a_tool_can_return_is_known():
    """An unknown code would end the command in a KeyError instead of a hint."""
    source = "".join(Path(m.__file__).read_text() for m in (server, server.here, tmux, slips))
    for code in ("NO_SESSION", "DAEMON_DOWN", "REFUSED", "BAD_ANSWER", "BAD_KIND",
                 "NO_SUCH_SESSION", "CODEX_THREAD", "BAD_PLANE", "NO_SUCH_PLANE",
                 "NOT_STARTABLE", "NO_TMUX", "NO_SUCH_TARGET", "BAD_ARRANGE", "TMUX_REFUSED"):
        assert f'"{code}"' in source and code in cli.ERRORS


@pytest.mark.parametrize("command,answer,code", [
    ("say", {"went": False, "why": "the quiet filter stopped it"}, "NOT_DELIVERED"),
    ("say", {"went": False, "code": "NO_SUCH_SESSION", "why": "no"}, "NO_SUCH_SESSION"),
    ("notify", {"pushed": False, "why": "this folder refuses"}, "NOT_PUSHED"),
    ("answer", {"answered": False, "why": "nothing yet"}, "PENDING"),
    ("presence", {"error": "down", "code": "DAEMON_DOWN"}, "DAEMON_DOWN"),
])
def test_a_no_is_told_from_a_yes(command, answer, code):
    assert cli.failure(command, answer)[0] == code


def test_a_yes_is_not_a_failure():
    assert cli.failure("say", {"went": True, "by": "socket", "why": None}) is None
    assert cli.failure("answer", {"answered": True, "value": True}) is None


def test_presence_prints_one_word_and_a_down_daemon_exits_3(monkeypatch, capsys):
    async def here():
        return {"where": "phone", "idle": 400.0}

    monkeypatch.setattr(server, "presence", here)
    cli.main(["presence"])
    assert capsys.readouterr().out == "phone\n"

    async def down():
        return {"error": "not answering", "code": "DAEMON_DOWN"}

    monkeypatch.setattr(server, "presence", down)
    with pytest.raises(SystemExit) as ended:
        cli.main(["presence"])
    assert ended.value.code == 3
    said = json.loads(capsys.readouterr().err)["error"]
    assert said["code"] == "DAEMON_DOWN" and said["retryable"] is True and said["hint"]


def test_a_bad_argument_is_a_structured_usage_error(capsys):
    with pytest.raises(SystemExit) as ended:
        cli.main(["answer"])
    assert ended.value.code == 2
    assert json.loads(capsys.readouterr().err)["error"]["code"] == "USAGE"


def test_sessions_project_fields_and_say_how_many_were_cut(monkeypatch, capsys):
    async def listed():
        return {"sessions": [{"session": f"s{i}", "name": f"n{i}", "folder": "/x",
                              "status": "idle", "waiting": 0} for i in range(3)]}

    monkeypatch.setattr(server, "sessions", listed)
    cli.main(["sessions", "--fields", "name", "--limit", "2"])
    out = json.loads(capsys.readouterr().out)
    assert out == {"sessions": [{"name": "n0"}, {"name": "n1"}], "shown": 2, "total": 3}
    with pytest.raises(SystemExit):
        cli.main(["sessions", "--fields", "colour"])
    assert "name" in json.loads(capsys.readouterr().err)["error"]["message"]


def test_prime_is_markdown_and_names_every_command(monkeypatch, capsys):
    async def status():
        return {"session": "deckhand", "folder": "/x", "where": "laptop", "daemon": "up",
                "next": "deckhand prime"}

    monkeypatch.setattr(cli, "status", status)
    cli.main(["prime"])
    out = capsys.readouterr().out
    assert out.startswith("# deckhand ") and "where=laptop" in out
    assert all(f"`deckhand {c['name']}" in out for c in cli.COMMANDS)
    cli.main(["prime", "--json"])
    assert json.loads(capsys.readouterr().out)["detected"]["where"] == "laptop"


@pytest.mark.parametrize("argv", [["clear"], ["--json", "rename"], ["input", "7"]])
def test_a_refused_verb_says_whose_it_is_instead_of_how_to_spell_it(argv, capsys):
    with pytest.raises(SystemExit) as ended:
        cli.main(argv)
    assert ended.value.code == 1
    said = json.loads(capsys.readouterr().err)["error"]
    assert said["code"] == "PERSON_ONLY" and said["retryable"] is False
    assert "POST /" in said["message"]  # names the route, so nobody has to go and find it


def test_every_refusal_is_named_where_an_agent_looks_and_none_shadows_a_command(monkeypatch,
                                                                                capsys):
    assert not set(refused.BY_VERB) & ({c["name"] for c in cli.COMMANDS} | {"prime"})
    routes = [row["route"] for row in refused.REFUSED]
    assert all(route in server.server.instructions for route in routes)

    async def status():
        return {"where": "laptop"}

    monkeypatch.setattr(cli, "status", status)
    cli.main(["prime"])
    out = capsys.readouterr().out
    assert all(route in out for route in routes) and str(cli.DOC) in out
    cli.main(["prime", "--json"])
    assert json.loads(capsys.readouterr().out)["refused"] == refused.REFUSED


def test_start_takes_only_a_provider_there_is(capsys):
    with pytest.raises(SystemExit) as ended:
        cli.main(["start", "--provider", "gemini"])
    assert ended.value.code == 2


def test_a_session_is_found_by_part_of_its_name_but_never_by_a_guess():
    live = [{"session_id": "abc-1", "name": "utt-review"}, {"session_id": "abd-2", "name": "utt"},
            {"session_id": "xyz-3", "name": "deckhand"}]
    assert server._match("utt", live)["session_id"] == "abd-2"
    assert server._match("deck", live)["session_id"] == "xyz-3"
    assert server._match("xy", live)["session_id"] == "xyz-3"
    assert server._match("ab", live) is None
