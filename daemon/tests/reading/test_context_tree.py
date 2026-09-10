"""The CLAUDE.md tree: what it finds, and the connectors it draws.

The walk is a directory listing and needs no test beyond "it found the files". The prefixes do:
whether a branch is still open at a level is the one piece of real logic here, and getting it
wrong draws a tree that is subtly, unreadably wrong rather than obviously broken.
"""

from __future__ import annotations

from pathlib import Path

from deckhand_daemon.reading import context


def _tree(root: Path, *folders: str) -> None:
    (root / "CLAUDE.md").write_text("project\n")
    for folder in folders:
        made = root / folder
        made.mkdir(parents=True, exist_ok=True)
        (made / "CLAUDE.md").write_text(f"{folder}\n")


def test_the_project_and_everything_under_it_is_found(tmp_path: Path) -> None:
    _tree(tmp_path, "app", "app/views", "daemon")
    (tmp_path / "GLOSSARY.md").write_text("words\n")
    (tmp_path / ".claude" / "rules").mkdir(parents=True)
    (tmp_path / ".claude" / "rules" / "naming.md").write_text("rule\n")
    found = {(doc.label, doc.kind) for doc in context.documents(str(tmp_path))}
    assert (tmp_path.name, "project") in found
    assert ("app", "descendant") in found
    assert ("app/views", "descendant") in found
    assert (tmp_path.name, "glossary") in found
    assert ("rules/naming", "rule") in found


def test_machinery_is_never_context(tmp_path: Path) -> None:
    """A CLAUDE.md inside node_modules or an _archive is somebody else's, or is dead."""
    _tree(tmp_path, "node_modules/thing", "_archive/2026-01/old", "real")
    labels = {doc.label for doc in context.documents(str(tmp_path))}
    assert "real" in labels
    assert not {label for label in labels if "node_modules" in label or "_archive" in label}


def test_a_branch_stays_open_until_its_last_child(tmp_path: Path) -> None:
    """`├──` while siblings follow, `└──` on the last, and a `│` held down the side of a
    branch that is still open above. This is the whole of what makes it read as a tree."""
    _tree(tmp_path, "app", "app/views", "zebra")
    drawn = {doc.label: doc.prefix for doc in context.documents(str(tmp_path))}
    # `app` has `zebra` after it, so its own corner is a tee...
    assert drawn["app"].endswith("├── ")
    # ...and its child is drawn beside a bar, because `app`'s branch is still open.
    assert drawn["app/views"].endswith("│   └── ")
    # Nothing follows `zebra` at its level, so it closes its branch.
    assert drawn["zebra"].endswith("└── ")


def test_tokens_are_atlas_own_estimate(tmp_path: Path) -> None:
    """Copied rather than re-picked, so the two tools never disagree about one file."""
    (tmp_path / "CLAUDE.md").write_text("x" * 250)
    assert context.documents(str(tmp_path))[-1].tokens == 100


def test_only_the_tree_opens_a_document(tmp_path: Path) -> None:
    _tree(tmp_path, "app")
    assert context.allowed(str(tmp_path), str(tmp_path / "app" / "CLAUDE.md")) is not None
    (tmp_path / "secret.md").write_text("no\n")
    assert context.allowed(str(tmp_path), str(tmp_path / "secret.md")) is None
