"""`deckhand` — the MCP server's sixteen tools as one shell command.

**One surface, three doors.** The daemon's routes are the API; `server.py` turns nine of them and
the skill's two slip scripts into tools, and two more over tmux; this file calls *those same functions*, so the command
and the tool cannot drift — `test_cli.py` fails the day a tool exists without a command. Nothing
here reaches the daemon or writes a slip on its own.

Built to the agent-friendly-cli contract: JSON when piped, a Markdown `prime`, every failure as
`{code, category, message, hint, retryable}`, and an exit status per category so an agent can
read the outcome off `$?`. Installed on PATH with `just install-cli`.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys
from pathlib import Path
from typing import Any, NoReturn, get_args

from .. import __version__
from . import refused, server, tmux
from .contract import COMMANDS, ERRORS, EXIT, SESSION_FIELDS

#: Every route, tool and command in one page, generated from the code (`daemon/tools/commands_doc.py`).
DOC = Path(__file__).resolve().parents[4] / "docs" / "commands.md"

PURPOSE = ("Reach the person — in this conversation when they are at the laptop or in the "
           "headset, on their phone when they are not — speak to the other Claude sessions on "
           "this Mac, and in their headset see what stands beside this session, put a page or a "
           "Mac window there, or start another session there — and organise the person's tmux: read "
           "every window and pane, then rename, group, move, swap, join, break, lay out, zoom "
           "or focus them.")

class Parser(argparse.ArgumentParser):
    """A bad argument is a structured `USAGE` failure like any other, not argparse's prose."""

    def error(self, message: str) -> NoReturn:
        _fail("USAGE", f"{message} — {self.format_usage().strip()}",
              machine=not sys.stdout.isatty())


def build_parser() -> Parser:
    parser = Parser(prog="deckhand", description=PURPOSE, epilog=(
        "Not here on purpose, the person's own: "
        f"{', '.join(refused.BY_VERB)}. `deckhand prime` says why; {DOC} has every route, "
        "tool and command."))
    parser.add_argument("--json", action="store_true", help="JSON even on a terminal")
    sub = parser.add_subparsers(dest="command", parser_class=Parser)
    sub.add_parser("prime", help="the whole contract, as Markdown (--json for the model)")
    for command in COMMANDS:
        sub.add_parser(command["name"], help=command["does"].replace("%", "%%"))  # argparse formats help
    sub.choices["sessions"].add_argument("--fields", help=f"comma list of {','.join(SESSION_FIELDS)}")
    sub.choices["sessions"].add_argument("--limit", type=int, default=50)
    ask = sub.choices["ask"]
    ask.add_argument("title", help="the question, or - to read it from stdin")
    ask.add_argument("--kind", default="confirm")
    ask.add_argument("--option", action="append", default=[])
    ask.add_argument("--note", default="")
    ask.add_argument("--question", action="append", default=[], dest="questions")
    ask.add_argument("--action", default="")
    ask.add_argument("--expires-hours", type=float, default=24.0)
    ask.add_argument("--key", default="")
    sub.choices["answer"].add_argument("id")
    sub.choices["answer"].add_argument("--wait", type=float, default=0.0)
    sub.choices["notify"].add_argument("line", help="what to say, or - to read it from stdin")
    sub.choices["read"].add_argument("session", help="name, id, unique id prefix or part of a name")
    sub.choices["read"].add_argument("--turns", type=int, default=1, help="0 for the whole transcript")
    sub.choices["read"].add_argument("--before", type=int, default=0, help="an answer's `older`, to page back")
    sub.choices["tmux"].add_argument("match", nargs="?", default="",
                                     help="only panes whose session, window, folder or Claude session holds it")
    sub.choices["say"].add_argument("session", help="name, id, unique id prefix or part of a name")
    sub.choices["say"].add_argument("text", help="what to say, or - to read it from stdin")
    sub.choices["end"].add_argument("sessions", nargs="+", help="names or ids, on any machine")
    sub.choices["end"].add_argument("--why", required=True, help="what the person reads")
    sub.choices["open"].add_argument("url", nargs="?", help="http(s), reachable from the headset")
    sub.choices["open"].add_argument("--window", type=int, help="an id from `deckhand windows`")
    sub.choices["open"].add_argument("--title")
    sub.choices["close"].add_argument("id")
    sub.choices["space"].add_argument("--full", action="store_true")
    sub.choices["start"].add_argument("folder", nargs="?", help="a listed project; default here")
    sub.choices["start"].add_argument("--provider", default="claude",
                                       choices=("claude", "codex", "opencode"))
    arrange = sub.choices["arrange"]
    arrange.add_argument("action", choices=get_args(tmux.Action))
    arrange.add_argument("target", help="session name, %%pane, @window, session:index, window name")
    arrange.add_argument("--to")
    arrange.add_argument("--name")
    arrange.add_argument("--layout", choices=tmux.LAYOUTS)
    arrange.add_argument("--split", default="right", choices=("right", "below"))
    for each in sub.choices.values():
        each.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
    return parser


def _text(value: str) -> str:
    return sys.stdin.read().strip() if value == "-" else value


async def _call(a: argparse.Namespace) -> dict[str, Any]:
    match a.command:
        case "presence":
            return await server.presence()
        case "whoami":
            return await server.whoami()
        case "sessions":
            return await server.sessions()
        case "ask":
            return await server.ask_on_phone(_text(a.title), kind=a.kind, options=a.option,
                                             note=a.note, questions=a.questions, action=a.action,
                                             expires_hours=a.expires_hours, key=a.key)
        case "answer":
            return await server.read_answer(a.id, wait_seconds=a.wait)
        case "notify":
            return await server.call_for_attention(_text(a.line))
        case "read":
            return await server.read_session(a.session, turns=a.turns,
                                             before=a.before)
        case "say":
            return await server.say_to_session(a.session, _text(a.text))
        case "end":
            return await server.request_end_session(a.sessions, a.why)
        case "open":
            return await server.open_plane(a.url, window=a.window, title=a.title)
        case "space":
            return await server.space(full=a.full)
        case "close":
            return await server.close_plane(a.id)
        case "windows":
            return await server.mac_windows()
        case "start":
            return await server.start_session(a.folder, provider=a.provider)
        case "tmux":
            return await server.tmux_tree(a.match)
        case "arrange":
            return await server.tmux_arrange(a.action, a.target, to=a.to, name=a.name,
                                             layout=a.layout, split=a.split)
    raise AssertionError(a.command)


#: The commands whose answer can be a "no": command → (the field that says yes, its code, and
#: what to say when the tool gave no reason).
NO: dict[str, tuple[str, str, str]] = {
    "say": ("went", "NOT_DELIVERED", "it was not said"),
    "notify": ("pushed", "NOT_PUSHED", "it was not pushed"),
    "answer": ("answered", "PENDING", "no answer yet"),
}


def failure(command: str, answer: dict[str, Any]) -> tuple[str, str] | None:
    """(code, message) when the answer is a failure or a "no", else None."""
    if "error" in answer:
        return answer.get("code", "REFUSED"), answer["error"]
    if command in NO and not answer.get((said := NO[command])[0]):
        return answer.get("code", said[1]), answer.get("why") or said[2]
    return None


def _fail(code: str, message: str, machine: bool) -> NoReturn:
    category, retryable, hint = ERRORS[code]
    if machine:
        print(json.dumps({"error": {"code": code, "category": category, "message": message,
                                    "hint": hint, "retryable": retryable}}, ensure_ascii=False),
              file=sys.stderr)
    else:
        print(f"error {code}: {message}\nhint: {hint}", file=sys.stderr)
    sys.exit(EXIT[category])


def _emit(data: dict[str, Any], machine: bool) -> None:
    if machine:
        print(json.dumps(data, ensure_ascii=False))
        return
    if (rows := data.get("sessions")) is not None:
        keys = list(rows[0]) if rows else []
        widths = {k: max(len(k), *(len(str(r.get(k, ""))) for r in rows)) for k in keys}
        for line in [dict(zip(keys, keys))] + rows:
            print("  ".join(str(line.get(k, "")).ljust(widths[k]) for k in keys).rstrip())
        if data["shown"] < data["total"]:
            print(f"showing {data['shown']} of {data['total']} — raise --limit", file=sys.stderr)
        return
    for key, value in data.items():
        print(f"{key:<9} {json.dumps(value, ensure_ascii=False) if isinstance(value, (dict, list)) else value}")


def _sessions(answer: dict[str, Any], a: argparse.Namespace, machine: bool) -> dict[str, Any]:
    rows = answer["sessions"]
    if a.fields:
        wanted = [f.strip() for f in a.fields.split(",") if f.strip()]
        if unknown := [f for f in wanted if f not in SESSION_FIELDS]:
            _fail("USAGE", f"no field {', '.join(unknown)}; there is {', '.join(SESSION_FIELDS)}",
                  machine)
        rows = [{f: r.get(f) for f in wanted} for r in rows]
    shown = rows[: max(a.limit, 0)]
    return {"sessions": shown, "shown": len(shown), "total": len(rows)}


async def status() -> dict[str, Any]:
    """What a bare `deckhand` says: enough to decide the next command, in one round trip."""
    who, where = await asyncio.gather(server.whoami(), server.presence())
    return {"session": who.get("name"), "folder": who.get("folder"),
            "where": where.get("where"), "daemon": "down" if "error" in where else "up",
            "next": "deckhand prime"}


def prime(detected: dict[str, Any]) -> str:
    commands = "\n".join(f"- `deckhand {c['name']}{' ' + c['args'] if c['args'] else ''}` — "
                         f"{c['does']} (MCP: `{c['tool']}`)" for c in COMMANDS)
    errors = "\n".join(f"- `{code}` — {cat}{', retryable' if retry else ''}: {hint}"
                       for code, (cat, retry, hint) in ERRORS.items())
    found = " · ".join(f"{k}={v}" for k, v in detected.items() if k != "next")
    return f"""# deckhand {__version__}
{PURPOSE}

## Start here
1. `deckhand presence` — `laptop` or `headset`: the person is reading this conversation, ask here
   and stop. `phone`: go on.
2. `deckhand ask "Ship it?" --action "…"` — prints the slip id; then end your turn: their signed
   answer arrives as your next message. Under 80 characters; detail in `--note`.
3. `deckhand answer <id>` — exit 4 until they answer; `verified` says their phone signed it.
4. Nothing to ask but they must know: `deckhand notify "Build done, 3 tests fail"`.

## Commands
- `deckhand` — status: this session, where the person is, whether the daemon answers
- `deckhand prime [--json]` — this contract
{commands}

## In the headset
1. `deckhand space` — `around_you`: your group and what stands beside you.
2. `deckhand open http://<slug>.atlas.local.jurrejan.com/` — a page beside you, in your group;
   opening it again hands back the same plane (`reused: true`).
3. `deckhand start [FOLDER]` — another session beside you; then `deckhand say <its name> "…"`
   to give it the work.
4. `deckhand close <id prefix>` — take a page or window away again.
When the person puts a page beside you, or takes one away, a message from the daemon says so;
`close` from here is closed as you, and nobody is told.

## In tmux
1. `deckhand tmux` — every window and pane, the Claude session in each, and `you`.
2. `deckhand arrange group utt --name review` — a window's `@group`; the headset follows it.
3. `deckhand arrange join utt --to deckhand` then `deckhand arrange layout deckhand --layout
   even-horizontal` — two sessions side by side; `break` takes one out again.
`focus` moves what the person is looking at: only when they asked.

## Output contract
- stdout is data: JSON when piped or with `--json`, aligned text on a terminal. `presence`
  prints one bare word either way unless `--json`.
- Failures go to stderr, as `{{"error": {{code, category, message, hint, retryable}}}}` when
  piped.
- Exit: 0 ok · 1 user, upstream or internal error · 2 usage · 3 daemon not answering, retry ·
  4 a "no": not said, not pushed, not answered yet.
- `-` for QUESTION, LINE or TEXT reads it from stdin.

## Error codes
{errors}

## Guardrails
- `say` is socket-only: the words arrive labelled as another Claude session, carrying none of
  the person's authority. Nothing here types into a pane, on purpose — do not go around it.
- A slip is a file in this session's own folder, `.deckhand/artifacts/`. Asking an answered
  decision again returns its answer; any other slip is replaced and its answer dropped.
- `notify` is for a finished long job or a stuck session, never for progress.
- `presence` moves the moment the person sits down or walks off: ask it again before each
  question, never cache it.
- `open` puts a plane in the person's headset, another machine on the LAN: prefer
  `https://<slug>.atlas.local.jurrejan.com`. localhost becomes this Mac's LAN address, which only
  answers if the server binds 0.0.0.0. A Mac window plane is view-only. `close` takes a plane,
  never a session: closing a session is the person's own press.
- `start` runs a new Claude Code session, only in a folder the project list names and
  Claude Code already trusts. It begins with no task, and nothing here can close it: start one
  when the work needs a second pair of hands, not to look busy.

## Not here on purpose
The person's own, so stop looking: `deckhand <verb>` for any of these answers `PERSON_ONLY` and
why. `curl` would still do it, which is why the reason is written down.
{refused.markdown()}

## Reference
`{DOC}` — every HTTP route, MCP tool and command, generated from the code.

## Detected
{found} · next: `deckhand presence`
"""


def main(argv: list[str] | None = None) -> None:
    # The `mcp` package logs every request httpx makes at INFO; stderr is for failures here.
    logging.getLogger("httpx").setLevel(logging.WARNING)
    argv = sys.argv[1:] if argv is None else argv
    # Before argparse, whose "invalid choice" would send an agent looking for the right spelling.
    verb = next((word for word in argv if not word.startswith("-")), "")
    if why := refused.BY_VERB.get(verb):
        _fail("PERSON_ONLY", f"there is no `deckhand {verb}`, on purpose: {why}",
              machine="--json" in argv or not sys.stdout.isatty())
    a = build_parser().parse_args(argv)
    machine = a.json or not sys.stdout.isatty()
    if a.command is None:
        _emit(asyncio.run(status()), machine)
        return
    if a.command == "prime":
        detected = asyncio.run(status())
        if a.json:
            print(json.dumps({"name": "deckhand", "version": __version__, "purpose": PURPOSE,
                              "commands": COMMANDS, "exit": EXIT,
                              "errors": {c: {"category": e[0], "retryable": e[1], "hint": e[2]}
                                         for c, e in ERRORS.items()},
                              "refused": refused.REFUSED, "doc": str(DOC),
                              "detected": detected}))
        else:
            print(prime(detected), end="")
        return
    answer = asyncio.run(_call(a))
    if failed := failure(a.command, answer):
        _fail(*failed, machine=machine)
    if a.command == "presence" and not a.json:
        print(answer["where"])
    elif a.command == "sessions":
        _emit(_sessions(answer, a, machine), machine)
    else:
        _emit(answer, machine)


if __name__ == "__main__":
    main()
