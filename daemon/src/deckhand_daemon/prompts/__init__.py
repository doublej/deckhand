"""Every prompt this daemon sends a model, out of the Python and into files a person can edit.

One markdown file per prompt, in the shape Claude Code writes an agent definition in: YAML
frontmatter for the settings the run needs — model, effort, turns, timeouts, the tool
descriptions — and the body is the prompt itself, verbatim, with nothing quoting or escaping it.
That last part is the whole point: a prompt in a triple-quoted Python string is a prompt nobody
edits, because editing it means opening a source file and minding its indentation.

Read at import, so the modules that use one keep their own `MODEL` and `TIMEOUT` and nothing
downstream has to know a file is involved. A prompt is a constant of this process: editing one
takes effect when the daemon restarts, the same as changing any other constant here would.

A missing or malformed file raises on import. That is deliberate — a daemon that starts without
its briefing prompt is a daemon that writes no briefings, and failing at the import is the one
moment anybody is looking at the log.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import yaml

FOLDER = Path(__file__).parent


@dataclass(frozen=True, slots=True)
class Prompt:
    """One prompt file: what it says, and the settings its run needs."""

    name: str
    body: str
    settings: dict

    def filled(self, **values: object) -> str:
        """The body with its {placeholders} replaced by what is passed here.

        Plain replacement rather than `str.format`, because the body is a file somebody edits: a
        literal brace in an example — a JSON snippet, a shell expansion — would otherwise make
        `format` raise on every prompt this ever built, and the person who typed the brace would
        have no way to connect the two.
        """
        text = self.body
        for key, value in values.items():
            text = text.replace("{" + key + "}", str(value))
        return text


def load(name: str) -> Prompt:
    """The prompt in `<name>.md`, beside this file."""
    path = FOLDER / f"{name}.md"
    front, body = _split(path.read_text(), path.name)
    settings = yaml.safe_load(front) or {}
    if not isinstance(settings, dict):
        raise TypeError(f"{path.name}: frontmatter is not a mapping")
    return Prompt(name=name, body=body, settings=settings)


def _split(text: str, where: str) -> tuple[str, str]:
    """Frontmatter and body, out of a file that opens with a `---` fence and closes it."""
    if not text.startswith("---\n"):
        raise ValueError(f"{where}: a prompt file starts with a --- frontmatter fence")
    front, fence, body = text[4:].partition("\n---\n")
    if not fence:
        raise ValueError(f"{where}: the frontmatter fence is never closed")
    return front, body.strip()
