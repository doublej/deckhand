"""`docs/commands.md` is the code's own tables, or this fails and says how to regenerate it."""

import importlib.util
from pathlib import Path

TOOL = Path(__file__).resolve().parents[2] / "tools" / "commands_doc.py"


def _generator():
    spec = importlib.util.spec_from_file_location("commands_doc", TOOL)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def test_the_command_reference_is_what_the_code_says():
    doc = _generator()
    on_disk = doc.DOC.read_text()
    assert doc.render(on_disk) == on_disk, (
        "docs/commands.md is out of date: uv run --directory daemon python tools/commands_doc.py")


def test_every_route_tool_and_command_is_on_the_page():
    """The other way to drift: a block the generator fills but nobody kept in the page."""
    doc = _generator()
    page = doc.DOC.read_text()
    spec = doc.app.openapi()
    routes = [f"`{m.upper()} {p}`" for p, ops in spec["paths"].items() for m in ops]
    assert all(route in page for route in routes)
    assert all(f"### `{name}`" in page for name in doc.tools())
    assert all(f"`deckhand {c['name']}`" in page for c in doc.cli.COMMANDS)
    assert "/Users/" not in page  # nothing of the machine that generated it
