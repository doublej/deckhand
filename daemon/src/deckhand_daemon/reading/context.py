"""Every CLAUDE.md a session in this folder is loaded with, drawn as a tree.

This is not the files a session touched — that is `files.py`, and it is bounded by the
transcript. This is the standing instructions a session in this folder *starts* with, whether it
has read them this run or not, which is a different question and the one people actually ask:
"what is in this session's head before I say anything to it?"

It is atlas's `atlas tree` in the daemon rather than a shell out to it. atlas prints ascii and
has no machine-readable mode, so parsing its output would be reading a picture — and the walk
itself is a directory listing, which is not worth a dependency on another tool's formatting
staying still. The one thing copied rather than re-picked is the token estimate: atlas uses
`length / 2.5` (`atlas-cli/src/commands/prime.ts`), so this does too and the two never disagree
about the same file.

The kinds are atlas's own words, in atlas's own order: the chain of folders above the project
each contributing one, the Mac-wide `~/.claude/CLAUDE.md`, the project's own, then everything
inside it — deeper CLAUDE.md files, the glossary, and the rules.
"""

from __future__ import annotations

import os
from dataclasses import asdict, dataclass
from pathlib import Path

#: atlas's estimate, copied rather than re-picked. See the module docstring.
CHARS_PER_TOKEN = 2.5
#: Machinery, not context. Dot directories are skipped in the walk and `.claude/rules` is
#: collected by name instead, which is the only one that carries anything.
SKIP = {".git", "node_modules", ".venv", "__pycache__", ".build", "DerivedData", "_archive"}
#: A monorepo can hold hundreds. A phone drawing a tree that long is drawing a wall.
MAX_DOCS = 80
#: How far down to look. Nothing anybody writes by hand sits deeper than this, and a folder full
#: of checked-out repos must not turn opening a tab into a scan of the disk.
MAX_DEPTH = 6


@dataclass(slots=True)
class Doc:
    """One document in the tree, ready to draw."""

    path: str
    #: The folder it speaks for, not the file name: every row is a `CLAUDE.md`, so printing the
    #: file name eighty times says nothing. atlas labels rows the same way.
    label: str
    #: ancestor, root, project, descendant, glossary or rule.
    kind: str
    #: The drawn connector — `"│   ├── "`. Worked out here so the phone draws the tree by
    #: printing it in a monospaced font rather than re-deriving which branches are still open.
    prefix: str
    size: int
    tokens: int

    def to_json(self) -> dict:
        return asdict(self)


def documents(cwd: str) -> list[Doc]:
    """The whole tree for one folder, in reading order."""
    folder = Path(cwd)
    if not folder.is_dir():
        return []
    rows = _chain(folder)
    rows += _inside(folder, len(rows))
    return _drawn(rows[:MAX_DOCS])


def allowed(cwd: str, wanted: str) -> Path | None:
    """The document at `wanted`, but only because it is in this folder's own tree.

    A deliberate second door onto `/sessions/{id}/file`, which is otherwise bounded by what the
    transcript named. The tree is the permission, exactly as the file listing is its own: these
    are the instructions a session in this folder is already running under, the set is computed
    rather than supplied, and nothing outside it is reachable through here.
    """
    for doc in documents(cwd):
        if doc.path == wanted:
            return Path(doc.path)
    return None


def _chain(folder: Path) -> list[tuple[int, Path, str, str]]:
    """Everything above the project: the folders on the way down to it, then the Mac's own.

    Ordered the way it is loaded rather than the way the filesystem is arranged, which is why
    `~/.claude` sits between the dev root and the project despite being neither's child.
    """
    home = Path.home()
    found: list[tuple[int, Path, str, str]] = []
    above = [p for p in reversed(folder.parents) if p == home or home in p.parents]
    for parent in above:
        if (doc := parent / "CLAUDE.md").is_file():
            found.append((len(found), doc, _tilde(parent), "ancestor"))
    if (root := home / ".claude" / "CLAUDE.md").is_file():
        found.append((len(found), root, "~/.claude", "root"))
    if (own := folder / "CLAUDE.md").is_file():
        found.append((len(found), own, folder.name, "project"))
    return found


def _inside(folder: Path, depth: int) -> list[tuple[int, Path, str, str]]:
    """Everything the project carries: deeper CLAUDE.md files, the glossary, the rules.

    A descendant sits one level under whichever descendant contains it, so the tree reads as the
    folders do. The glossary and the rules are leaves of the project itself — they are not
    folders and there is nothing under them.
    """
    found = []
    # Walked once, not once per row: this used to call `_walk` inside the loop, which is a whole
    # filesystem walk per descendant. On a folder with a dozen of them the route timed out.
    subs = _walk(folder)
    for sub in subs:
        under = sum(1 for other in subs if other != sub and other in sub.parents)
        found.append((depth + under, sub / "CLAUDE.md", _under(folder, sub), "descendant"))
    if (glossary := folder / "GLOSSARY.md").is_file():
        found.append((depth, glossary, folder.name, "glossary"))
    for rule in sorted((folder / ".claude" / "rules").glob("*.md")):
        found.append((depth, rule, f"rules/{rule.stem}", "rule"))
    return found


def _walk(folder: Path) -> list[Path]:
    """Every folder under this one carrying a CLAUDE.md, machinery pruned as we go.

    Pruned during the walk rather than filtered after it: `node_modules` is where the time goes,
    and there is no point reading it to throw it away.
    """
    found = []
    for root, dirs, files in os.walk(folder):
        dirs[:] = sorted(d for d in dirs if d not in SKIP and not d.startswith("."))
        # Deep enough to reach anything anyone files by hand, and shallow enough that a folder
        # holding a hundred checked-out repos cannot turn one tab into a full-disk scan.
        if len(Path(root).relative_to(folder).parts) >= MAX_DEPTH:
            dirs[:] = []
        if Path(root) != folder and "CLAUDE.md" in files:
            found.append(Path(root))
            if len(found) >= MAX_DOCS:
                break
    return found


def _drawn(rows: list[tuple[int, Path, str, str]]) -> list[Doc]:
    """The rows with their connectors worked out, and anything unreadable dropped."""
    depths = [depth for depth, *_ in rows]
    found = []
    for index, (depth, path, label, kind) in enumerate(rows):
        try:
            size = path.stat().st_size
        except OSError:
            continue
        found.append(Doc(
            path=str(path),
            label=label,
            kind=kind,
            prefix=_prefix(depth, depths[index + 1:]),
            size=size,
            tokens=round(size / CHARS_PER_TOKEN),
        ))
    return found


def _prefix(depth: int, later: list[int]) -> str:
    """`"│   ├── "` — a bar for every level still open above this row, then its own corner."""
    if depth == 0:
        return ""
    bars = "".join("│   " if _open(later, above) else "    " for above in range(1, depth))
    return bars + ("├── " if _open(later, depth) else "└── ")


def _open(later: list[int], depth: int) -> bool:
    """Whether anything below this row is still a sibling at `depth`, rather than an aunt."""
    for other in later:
        if other < depth:
            return False
        if other == depth:
            return True
    return False


def _tilde(folder: Path) -> str:
    """`~/dev`, the way a person says it and the way atlas prints it."""
    home = Path.home()
    return f"~/{folder.relative_to(home)}" if home in folder.parents or folder == home else str(folder)


def _under(folder: Path, sub: Path) -> str:
    return str(sub.relative_to(folder))
