"""What a session can be told to do by name: its slash commands and its skills.

A phone dictates a sentence well and spells `/orchestrate-sessions` badly, which is the whole
reason this exists. The names are on the Mac already — Claude Code reads them out of `commands/`
and `skills/` under `~/.claude` and under the project — so the phone asks for the list and puts
one at the front of the words it was going to send anyway.

Both kinds are one thing here, because from the phone they are one thing: a word you type after a
slash. They differ in where the file lives and what it means to Claude Code, and `kind` carries
that for anyone who wants to show them apart.

Nothing here writes and nothing here runs a command. A chosen name is text at the front of a
prompt, delivered down the same lane as any other words — which is why it has to go by keyboard,
and `deliver` is where that is enforced.
"""

from __future__ import annotations

import os
from dataclasses import asdict, dataclass
from pathlib import Path

import yaml

from ..log import log

# Enough of a file to hold its frontmatter. A SKILL.md runs to hundreds of lines and only the
# block at the top is wanted; reading all of ~190 of them per request is the difference between
# a listing that costs nothing and one nobody opens twice.
PEEK = 4096
# What a name may be made of. Claude Code's own rule, and it keeps a stray file in the folder —
# a README, something half-saved by an editor — from being offered as a command that does not run.
ALLOWED = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_:")


@dataclass(frozen=True, slots=True)
class Command:
    """One name, and enough about it to choose between two hundred."""

    name: str
    description: str
    #: `argument-hint` where the command declares one — what to say after the name.
    hint: str
    #: "command" or "skill".
    kind: str
    #: "project" or "user". A project one shadows a user one of the same name, as it does on the Mac.
    scope: str

    def to_json(self) -> dict:
        return asdict(self)


def claude_home() -> Path:
    return Path(os.environ.get("DECKHAND_CLAUDE_HOME", Path.home() / ".claude"))


def commands(cwd: str) -> list[Command]:
    """Every name this session could be handed, project before user, commands before skills.

    Project shadows user on a collision, which is Claude Code's own precedence — offering both
    would be offering a choice that does not exist, since only one of them will run.
    """
    found: dict[str, Command] = {}
    # Later writes lose, so the ones that shadow are read first.
    for root, scope in ((Path(cwd) / ".claude", "project"), (claude_home(), "user")):
        for command in _under(root, scope):
            found.setdefault(command.name, command)
    return sorted(found.values(), key=lambda c: (c.kind != "command", c.name))


def _under(root: Path, scope: str) -> list[Command]:
    """One root's worth, both kinds. A root that is not there is not an error — most projects
    have no `.claude/commands` at all, and a Mac with no skills folder is a new Mac."""
    return _files(root / "commands", scope) + _skills(root / "skills", scope)


def _files(folder: Path, scope: str) -> list[Command]:
    """`commands/feature.md` is `/feature`; `commands/git/amend.md` is `/git:amend`.

    The nesting is the namespace, which is Claude Code's rule and not one invented here — a
    phone offering `/amend` for a file it will have to type as `/git:amend` is offering a name
    that does nothing.
    """
    out = []
    for path in sorted(folder.rglob("*.md")):
        name = ":".join(path.relative_to(folder).with_suffix("").parts)
        if not name or set(name) - ALLOWED:
            continue
        head = _head(path)
        out.append(Command(name=name,
                           description=str(head.get("description", "")).strip(),
                           hint=_hint(head.get("argument-hint")),
                           kind="command",
                           scope=scope))
    return out


def _skills(folder: Path, scope: str) -> list[Command]:
    """A skill is its folder, and its `SKILL.md` says what it is for.

    The frontmatter's own `name` wins over the folder's where it has one, because that is the
    name Claude Code answers to — the two are almost always the same and the exception is the
    one worth getting right.
    """
    out = []
    for path in sorted(folder.glob("*/SKILL.md")):
        head = _head(path)
        name = str(head.get("name") or path.parent.name).strip()
        if not name or set(name) - ALLOWED:
            continue
        out.append(Command(name=name,
                           description=str(head.get("description", "")).strip(),
                           hint="",
                           kind="skill",
                           scope=scope))
    return out


def _hint(given: object) -> str:
    """`argument-hint` is a string in most commands and a list in some, and the phone shows it to
    a person — so a list has to read as words rather than as `['a thing to analyse']`."""
    if isinstance(given, list):
        return " ".join(str(part).strip() for part in given if str(part).strip())
    return str(given).strip() if given else ""


def _head(path: Path) -> dict:
    """The YAML frontmatter, or an empty one.

    Nothing here raises. A file being written as this reads it, one with no frontmatter, one whose
    frontmatter is not a mapping, and one that is not text at all all mean the same thing to a
    listing: a name with nothing said about it, which is still a name worth offering.
    """
    try:
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            head = handle.read(PEEK)
    except OSError as error:
        log.warning("could not read %s: %s", path, error)
        return {}
    if not head.startswith("---"):
        return {}
    end = head.find("\n---", 3)
    if end < 0:
        return {}
    try:
        block = yaml.safe_load(head[3:end])
    except yaml.YAMLError as error:
        _grumble(path, error)
        return {}
    return block if isinstance(block, dict) else {}


#: Files whose frontmatter has already been complained about. Unlike the `OSError` above — a file
#: caught mid-write, which is worth hearing about every time because it is different every time —
#: broken YAML does not repair itself, and this is read afresh on every `/commands`. Seven files
#: on this Mac wrote 2429 bytes into the log on each one, all of them `argument-hint: [a] [b]`,
#: which Claude Code itself reads perfectly well. Bounded by the number of command files there
#: are, which is the set being walked anyway.
_grumbled: set[Path] = set()


def _grumble(path: Path, error: Exception) -> None:
    """Say what could not be read, once per file, on one line.

    One line because a `yaml.YAMLError` renders as six of them — the message, the position, and
    two lines of pointer art — and `log.py`'s whole premise is one event per line.
    """
    if path in _grumbled:
        return
    _grumbled.add(path)
    log.warning("could not read the frontmatter of %s: %s", path, str(error).splitlines()[0])
