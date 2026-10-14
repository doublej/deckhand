"""Write the generated half of `docs/commands.md` out of the code, or say that it is stale.

    uv run --directory daemon python tools/commands_doc.py          # rewrite the tables
    uv run --directory daemon python tools/commands_doc.py --check  # exit 1 when out of date

The page is prose around blocks fenced `<!-- generated:NAME -->` … `<!-- /generated:NAME -->`, and
only what is between a pair is ever rewritten: the prose is edited by hand and the tables never
are. Routes come from the app's own OpenAPI table and their docstrings, tools from the MCP server's
own list, commands from `cli.COMMANDS`, `cli.ERRORS` and `cli.NO`, refusals from `mcp/refused.py`
— so one added without regenerating fails `tests/mcp/test_commands_doc.py`.

Two columns are read out of source rather than declared, and say less than everything. A route's
errors are what its own body raises, plus 401 for the token, 404 where it looks a session up and
422 for FastAPI's validation; a raise inside a helper is not seen. A tool's routes and codes are
what its body and the server's own `_helpers` it calls name.
"""

from __future__ import annotations

import asyncio
import inspect
import json
import re
import sys
from pathlib import Path

from fastapi.routing import APIRoute

from deckhand_daemon.app import app
from deckhand_daemon.mcp import cli, refused, server

DOC = Path(__file__).resolve().parents[2] / "docs" / "commands.md"
BLOCK = re.compile(r"(<!-- generated:(\w+) -->\n).*?(<!-- /generated:\2 -->)", re.DOTALL)
REACH = re.compile(r'reach\(\s*"(\w+)",\s*f?"([^"]+)"')
SCRIPT = re.compile(r'_script\("([\w.]+)"')
CODE = re.compile(r'"([A-Z][A-Z_]+)"')
RAISED = re.compile(r"HTTPException\(\s*(?:status_code=)?(\d{3})")
LOOKUP = re.compile(r"\b(?:session_or_404|live_session)\(")
#: What `here.reach` itself can answer, on any call.
REACHED = {"DAEMON_DOWN", "REFUSED", "BAD_ANSWER"}
TOKEN = "x-deckhand-token"


def cell(text: object) -> str:
    return " ".join(str(text).split()).replace("|", "\\|")


def first_paragraph(doc: str | None) -> str:
    return inspect.cleandoc(doc or "").split("\n\n")[0] or "—"


# The MCP tools, and what their bodies name.


def tools() -> dict:
    return {t.name: t for t in asyncio.run(server.server.list_tools())}


def source(name: str) -> str:
    """A tool's body, and the body of every `_helper` of the server's it calls, once each."""
    seen: set[str] = set()
    todo, text = [name], []
    while todo:
        if (each := todo.pop()) in seen:
            continue
        seen.add(each)
        body = inspect.getsource(getattr(server, each))
        text.append(body)
        todo += [n for n in re.findall(r"\b(_\w+)\(", body)
                 if inspect.isfunction(getattr(server, n, None))]
    return "\n".join(text)


def calls(body: str) -> str:
    routes = [f"`{m} {re.sub(r'{[^}]*}', '{id}', p)}`" for m, p in REACH.findall(body)]
    scripts = [f"`skills/deckhand/scripts/{s}`" for s in SCRIPT.findall(body)]
    return ", ".join(dict.fromkeys(routes + scripts)) or "this session's own record"


def codes(body: str) -> list[str]:
    found = {c for c in CODE.findall(body) if c in cli.ERRORS}
    return sorted(found | (REACHED if "reach(" in body else set()))


def kind(schema: dict) -> str:
    if "enum" in schema:
        return "|".join(map(str, schema["enum"]))
    if "anyOf" in schema:
        return "|".join(kind(s) for s in schema["anyOf"] if s.get("type") != "null")
    if schema.get("type") == "array":
        return f"{kind(schema.get('items', {}))}[]"
    return schema.get("type", "any")


def arguments(schema: dict) -> str:
    required = set(schema.get("required", []))
    said = []
    for name, each in schema.get("properties", {}).items():
        default = "" if name in required else f" = {json.dumps(each.get('default'))}"
        said.append(f"`{name}`: {kind(each)}{default}")
    return ", ".join(said) or "—"


def readonly(tool) -> bool:
    return bool(tool.annotations and tool.annotations.read_only_hint)


# The blocks.


def parity() -> str:
    listed = tools()
    rows = ["| Command | MCP tool | Reaches | Reads only |", "|---|---|---|---|"]
    for c in cli.COMMANDS:
        rows.append(row(f"`deckhand {c['name']}`", f"`{c['tool']}`", calls(source(c["tool"])),
                        "yes" if readonly(listed[c["tool"]]) else "no"))
    return "\n".join(rows)


def row(*cells: object) -> str:
    return "| " + " | ".join(cell(c) for c in cells) + " |"


def refusals() -> str:
    rows = ["| Verbs | What does it for the person | Why no tool or command |", "|---|---|---|"]
    rows += [row(", ".join(f"`{v}`" for v in r["verbs"].split()), f"`{r['route']}`", r["why"])
             for r in refused.REFUSED]
    return "\n".join(rows)


def commands() -> str:
    rows = ["| Command | Arguments | MCP tool | Fails with | Does |", "|---|---|---|---|---|"]
    for c in cli.COMMANDS:
        failed = codes(source(c["tool"])) + ([cli.NO[c["name"]][1]] if c["name"] in cli.NO else [])
        rows.append(row(f"`deckhand {c['name']}`", f"`{c['args']}`" if c["args"] else "—",
                        f"`{c['tool']}`", ", ".join(f"`{x}`" for x in failed), c["does"]))
    exits: dict[int, list[str]] = {}
    for category, status in cli.EXIT.items():
        exits.setdefault(status, []).append(category)
    rows += ["", "| Exit | Categories |", "|---|---|", "| 0 | ok |"]
    rows += [row(s, ", ".join(c)) for s, c in sorted(exits.items())]
    rows += ["", "| Code | Category | Retryable | Hint |", "|---|---|---|---|"]
    rows += [row(f"`{code}`", cat, "yes" if retry else "no", hint)
             for code, (cat, retry, hint) in cli.ERRORS.items()]
    return "\n".join(rows)


def mcp() -> str:
    out = []
    for name, tool in tools().items():
        body = source(name)
        out += [f"### `{name}` — {'reads only' if readonly(tool) else 'writes'}", "",
                f"Arguments: {arguments(tool.input_schema)}  ",
                f"Reaches: {calls(body)}  ",
                f"Fails with: {', '.join(f'`{c}`' for c in codes(body)) or '—'}", "",
                inspect.cleandoc(tool.description or ""), ""]
    return "\n".join(out).rstrip()


def endpoints() -> dict[tuple[str, str], object]:
    def walk(router):
        for route in router.routes:
            if isinstance(route, APIRoute):
                yield route
            elif (inner := getattr(route, "original_router", None)) is not None:
                yield from walk(inner)
    return {(m.lower(), r.path): r.endpoint for r in walk(app.router) for m in r.methods}


def http_arguments(op: dict, spec: dict) -> str:
    said = []
    for p in op.get("parameters", []):
        if p["in"] == "query":
            default = f" = {json.dumps(p['schema']['default'])}" if "default" in p["schema"] else ""
            meant = f" ({p['description']})" if p.get("description") else ""
            said.append(f"`?{p['name']}`: {kind(p['schema'])}{default}{meant}")
    for media, held in op.get("requestBody", {}).get("content", {}).items():
        schema = held.get("schema", {})
        if ref := schema.get("$ref"):
            schema = spec["components"]["schemas"][ref.rsplit("/", 1)[1]]
        where = "form" if "multipart" in media else "body"
        required = set(schema.get("required", []))
        fields = [f"{n}{'' if n in required else '?'}" for n in schema.get("properties", {})]
        said.append(f"{where} `{{{', '.join(fields)}}}`" if fields else f"{where}: JSON object")
    return ", ".join(said) or "—"


def http() -> str:
    spec, found = app.openapi(), endpoints()
    groups: dict[str, list[str]] = {}
    for path, operations in spec["paths"].items():
        for method, op in operations.items():
            body = inspect.getsource(found[(method, path)])
            answers = [c for c in op["responses"] if c.startswith("2")]
            params = [p["name"] for p in op.get("parameters", [])]
            errors = set(RAISED.findall(body))
            # FastAPI lists a 422 wherever there is a parameter, and the token header with its
            # default of "" is one that can never fail to parse.
            if set(params) - {TOKEN} or "requestBody" in op:
                errors.add("422")
            if TOKEN in params:
                errors.add("401")
            if LOOKUP.search(body):
                errors.add("404")
            groups.setdefault((op.get("tags") or ["core"])[0], []).append(row(
                f"`{method.upper()} {path}`", http_arguments(op, spec), ", ".join(answers),
                ", ".join(sorted(errors)) or "—", first_paragraph(op.get("description"))))
    out = []
    for tag, rows in groups.items():
        out += [f"### {tag}", "", "| Route | Arguments | Answers | Errors | What it does |",
                "|---|---|---|---|---|", *rows, ""]
    return "\n".join(out).rstrip()


BLOCKS = {"parity": parity, "refused": refusals, "cli": commands, "mcp": mcp, "http": http}


def render(text: str) -> str:
    filled: set[str] = set()

    def fill(found: re.Match) -> str:
        filled.add(found.group(2))
        return f"{found.group(1)}{BLOCKS[found.group(2)]()}\n{found.group(3)}"

    out = BLOCK.sub(fill, text)
    if missing := set(BLOCKS) - filled:
        raise SystemExit(f"{DOC.name} has no block for {', '.join(sorted(missing))}")
    return out


def main() -> int:
    text = DOC.read_text()
    fresh = render(text)
    if "--check" not in sys.argv[1:]:
        DOC.write_text(fresh)
        return 0
    if fresh != text:
        print(f"{DOC.name} is out of date: uv run --directory daemon python tools/commands_doc.py",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
