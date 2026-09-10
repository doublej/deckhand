#!/usr/bin/env python3
"""Write a slip — one HTML page a person answers on their phone — from arguments.

A slip is cheap to answer and expensive to write: the pick page alone is a hundred and nine
lines, and an agent asking a two-option question should not be emitting a hundred lines of HTML
to do it. This copies the matching page out of `templates/` (symlinks to Deckhand's own `demos/`,
so there is one copy of every page and `just demo-check` gates it) and swaps in a title, a slug
and a list.

Nothing here talks to the daemon, because nothing needs to: a slip is a file in the session's own
`cwd`, which is the whole reason it needs no tool. It goes under `.deckhand/artifacts/<session
id>/`, so only the session that asked lists it and the answer comes back to the session that
asked. `$CLAUDE_CODE_SESSION_ID` is that id and is in every Bash call Claude Code makes; with it
unset — a person running this in a terminal — the slip is written flat, which is the older scope
and means the folder rather than a session.

    slip.py --kind confirm --title "Tag 0.4.0 and push it?" --option "Tag and push"
    slip.py --kind pick --title "Which branch" --option develop --option main
    slip.py --kind text --title "What should this session be called?"
    slip.py --kind aloud --title "Before I start" --question "scope:How far should this go?"

Prints the path it wrote. Four kinds are mechanical. `form` and `tweak` are not — copy those out
of `templates/` by hand and edit them.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import sys
from pathlib import Path

# `templates/` sits beside `scripts/`, and resolving first is what makes this work through the
# `~/.claude/skills/deckhand` symlink: the templates are relative links into the repo's `demos/`.
TEMPLATES = Path(__file__).resolve().parent.parent / "templates"
# The daemon's own rule for an artifact id, copied from `artifacts.ID` — one segment, so `..`
# cannot be spelled and no path can. A slug it refuses is a slip the phone never lists.
SLUG = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}")


def buildSlug(title: str) -> str:
    """A readable id out of the title, the way a person would have typed one."""
    made = re.sub(r"[^A-Za-z0-9]+", "-", title).strip("-").lower()[:64]
    return made or "slip"


def swap(page: str, pattern: str, replacement: str) -> str:
    """Replace exactly one match, or say the template moved.

    Loudly rather than silently: these anchors are demo pages another agent edits, and a slip
    that quietly kept the demo's own question is worse than a script that refuses to write one.
    """
    page, hits = re.subn(pattern, lambda _: replacement, page, count=1, flags=re.DOTALL)
    if hits != 1:
        sys.exit(f"slip.py: the template no longer has {pattern!r} — the demo page moved under it")
    return page


def fillCommon(page: str, title: str, slug: str, note: str) -> str:
    """The four things every page has: its name, its id, its question and the line under it."""
    page = swap(page, r"<title>.*?</title>", f"<title>{html.escape(title)}</title>")
    page = swap(page, r'<p class="eyebrow" id="slug">.*?</p>',
                f'<p class="eyebrow" id="slug">{html.escape(slug)}</p>')
    page = swap(page, r"<h1>.*?</h1>", f"<h1>{html.escape(title)}</h1>")
    lead = f'\n  <p class="lead">{html.escape(note)}</p>' if note else ""
    return swap(page, r'\n\s*<p class="lead">.*?</p>', lead)


def fillConfirm(page: str, options: list[str]) -> str:
    """Yes and no, in that order — the primary button is what you are asking for."""
    yes = options[0] if options else "Go ahead"
    no = options[1] if len(options) > 1 else "Not yet"
    page = swap(page, r"\n\s*<h2>What ran</h2>\s*<ul>.*?</ul>", "")
    page = swap(page, r'<button id="no">.*?</button>',
                f'<button id="no">{html.escape(no)}</button>')
    page = swap(page, r'<button id="yes" class="primary">.*?</button>',
                f'<button id="yes" class="primary">{html.escape(yes)}</button>')
    # The page says back what you answered, in the words on the buttons, so the two have to move
    # together — a reopened confirm reading "You answered: Tag and push" under different buttons
    # is the page lying about its own state.
    return swap(page, r'\(before\.answer \? ".*?" : ".*?"\)',
                f"(before.answer ? {json.dumps(yes)} : {json.dumps(no)})")


def fillPick(page: str, options: list[str]) -> str:
    """One row per option, plus the row that takes a typed answer.

    `name="branch"` stays: the page's own script selects on it, and the last row's empty value is
    what tells that script to show the field. Both are the template's, not this script's.
    """
    if not options:
        sys.exit("slip.py: a pick needs at least one --option")
    rows = "".join(
        f"\n    <label>\n      <span>{html.escape(choice)}</span>"
        f'\n      <input type="radio" name="branch" value="{html.escape(choice)}">\n    </label>'
        for choice in options
    )
    rows += ('\n    <label>\n      <span>Something else<small>Say it yourself.</small></span>'
             '\n      <input type="radio" name="branch" value="">\n    </label>')
    page = swap(page, r"\n\s*<h2>Branch</h2>", "")
    page = swap(page, r'<div class="rows">.*?</div>', f'<div class="rows">{rows}\n  </div>')
    return swap(page, r'placeholder="Branch name" aria-label="Branch name"',
                'placeholder="Something else" aria-label="Something else"')


def fillText(page: str, options: list[str]) -> str:
    """One field, empty, with whatever the first option says over it."""
    label = options[0] if options else "Answer"
    page = swap(page, r'<label class="eyebrow" for="name">.*?</label>',
                f'<label class="eyebrow" for="name">{html.escape(label)}</label>')
    page = swap(page, r'<input id="name" type="text" value=".*?"',
                '<input id="name" type="text" value=""')
    return swap(page, r'\n\s*<p class="hint">Renaming runs.*?</p>', "")


def fillAloud(page: str, questions: list[str]) -> str:
    """The declaration block, which is the whole of what an aloud slip is.

    The app reads this block out of the HTML and draws one talk card per question. The page's own
    script renders the same questions from the same block, so there is nothing to keep in step.
    """
    if not questions:
        sys.exit("slip.py: an aloud slip needs at least one --question id:text")
    asked = []
    for pair in questions:
        said, _, ask = pair.partition(":")
        if not said.strip() or not ask.strip():
            sys.exit(f"slip.py: --question wants id:text, got {pair!r}")
        asked.append({"id": said.strip(), "ask": ask.strip()})
    # `</` closed as `<\/` so a question containing `</script>` cannot end the block early. It is
    # still ordinary JSON — `\/` is a valid escape — so the app parses it unchanged.
    block = json.dumps({"questions": asked}, indent=2, ensure_ascii=False).replace("</", "<\\/")
    page = swap(page, r"\n\s*<!--\s*THE ONLY THING TO EDIT\..*?-->", "")
    return swap(page, r'<script type="application/json" id="deckhand-aloud">.*?</script>',
                f'<script type="application/json" id="deckhand-aloud">\n{block}\n  </script>')


def main() -> int:
    parse = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parse.add_argument("--kind", required=True, choices=("confirm", "pick", "text", "aloud"))
    parse.add_argument("--title", required=True, help="the question, and the slip's name")
    parse.add_argument("--slug", help="the artifact id; made from the title when left out")
    parse.add_argument("--note", default="", help="the line under the question")
    parse.add_argument("--option", action="append", default=[], metavar="TEXT",
                       help="pick: one row. confirm: the yes label, then the no label. "
                            "text: the field's label")
    parse.add_argument("--question", action="append", default=[], metavar="ID:TEXT",
                       help="aloud: one spoken question, keyed by id")
    parse.add_argument("--dir", default=".", metavar="DIR",
                       help="the session's own folder (default: here). Nothing walks upward "
                            "looking for one, so a slip written elsewhere is invisible")
    parse.add_argument("--session", default=os.environ.get("CLAUDE_CODE_SESSION_ID", ""),
                       metavar="ID",
                       help="whose slip this is (default: $CLAUDE_CODE_SESSION_ID). Empty writes "
                            "it to the folder, where every session working there sees it")
    said = parse.parse_args()

    slug = said.slug or buildSlug(said.title)
    if not SLUG.fullmatch(slug):
        sys.exit(f"slip.py: {slug!r} is not a slip id — letters, digits, - and _, one segment")
    # Loudly rather than flat: the daemon holds a session id to this same rule, so a slip filed
    # under one it refuses is one the phone never lists — the failure nobody notices.
    if said.session and not SLUG.fullmatch(said.session):
        sys.exit(f"slip.py: {said.session!r} is not a session id — one segment, no dot, no slash")

    page = fillCommon((TEMPLATES / f"{said.kind}.html").read_text(), said.title, slug, said.note)
    if said.kind == "aloud":
        page = fillAloud(page, said.question)
    else:
        page = {"confirm": fillConfirm, "pick": fillPick, "text": fillText}[said.kind](
            page, said.option)

    folder = Path(said.dir).expanduser().resolve() / ".deckhand" / "artifacts" / said.session
    folder.mkdir(parents=True, exist_ok=True)
    where = folder / f"{slug}.html"
    where.write_text(page)
    # An answer beside a page that has just been rewritten answers the old question, and the
    # phone would draw the slip as answered. Deleting it is how `docs/artifacts.md` says to ask
    # again, and rewriting a slip is asking again.
    (folder / f"{slug}.answer.json").unlink(missing_ok=True)
    print(where)
    return 0


if __name__ == "__main__":
    sys.exit(main())
