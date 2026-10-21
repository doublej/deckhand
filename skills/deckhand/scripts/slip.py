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
asked. `$CLAUDE_CODE_SESSION_ID` is that id and is in every Bash call Claude Code makes, as
`$OPENCODE_SESSION_ID` is in every shell OpenCode runs; with neither set — a person running this
in a terminal — the slip is written flat, which is the older scope
and means the folder rather than a session.

    slip.py --kind confirm --title "Tag 0.4.0 and push it?" --option "Tag and push" \\
            --action "tag 0.4.0 on develop and push the tag, nothing else"
    slip.py --kind pick --title "Which branch" --option develop --option main
    slip.py --kind text --title "What should this session be called?"
    slip.py --kind aloud --title "Before I start" --question "scope:How far should this go?"
    slip.py --kind confirm --title "Ship it?" --image ~/dev/x/before.png --image ~/dev/x/after.png

**A picture named is a picture shown.** Any image path in the title or the note is attached to the
page on its own, and a path that does not exist stops the script: "see ~/shots/a.png" on a phone
is a sentence nobody can follow. `--image` attaches one the words do not name.

Prints the path it wrote. Four kinds are mechanical. `form` and `tweak` are not — copy those out
of `templates/` by hand and edit them.

**Confirm, pick and text are decisions**: four `<meta>` tags in the head say so, with the
choices, `--action` (what a yes allows, required for a confirm) and when the question lapses
(`--expires-hours`, 24 by default). The phone answers one only with a signature from its own key,
and the daemon types that answer into this session as the person's next message — so ask, end the
turn, and the answer arrives. Asking an answered decision again under the same id (`--key`, else
the slug) does not rewrite it: the existing answer is printed instead, as JSON — `id`,
`"answered": true`, and what `answer.py` prints.
"""

from __future__ import annotations

import argparse
import base64
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import answer  # beside this file: the one reader of an answer, verified or not

# `templates/` sits beside `scripts/`, and resolving first is what makes this work through the
# `~/.claude/skills/deckhand` symlink: the templates are relative links into the repo's `demos/`.
TEMPLATES = Path(__file__).resolve().parent.parent / "templates"
# The daemon's own rule for an artifact id, copied from `artifacts.ID` — one segment, so `..`
# cannot be spelled and no path can. A slug it refuses is a slip the phone never lists.
SLUG = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}")


# An absolute or `~/` path to a picture, however the agent wrote the sentence around it.
IMAGE_PATH = re.compile(r"(?:~|/)[^\s,;()\"'<>]*?\.(?:png|jpe?g|gif|webp)\b", re.IGNORECASE)
# One picture is kept under this once shrunk, so a few of them never make the page too big for
# the phone to be served (the daemon refuses a page over 4 MB).
IMAGE_BUDGET = 700_000
MIME = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
        ".gif": "image/gif", ".webp": "image/webp"}


def namedImages(*texts: str) -> list[str]:
    """Every picture path the words mention, in order, once."""
    found: list[str] = []
    for text in texts:
        for path in IMAGE_PATH.findall(text):
            if path not in found:
                found.append(path)
    return found


def embedImage(path: str) -> str:
    """One picture as a `<figure>` with a `data:` URI — the page may fetch nothing, so it carries it.

    Shrunk with `sips` (always on a Mac) when it is large; a picture that is still too big is
    refused rather than silently left out.
    """
    source = Path(path).expanduser()
    if not source.is_file():
        sys.exit(f"slip.py: {path} is mentioned or attached but is not a file")
    data, mime = source.read_bytes(), MIME[source.suffix.lower()]
    if len(data) > IMAGE_BUDGET and shutil.which("sips"):
        with tempfile.TemporaryDirectory() as scratch:
            small = Path(scratch) / "small.jpg"
            subprocess.run(["sips", "-Z", "1280", "-s", "format", "jpeg", str(source),
                            "--out", str(small)], check=True, capture_output=True)
            data, mime = small.read_bytes(), "image/jpeg"
    if len(data) > 2 * IMAGE_BUDGET:
        sys.exit(f"slip.py: {path} is {len(data)} bytes even shrunk — attach a smaller crop")
    uri = f"data:{mime};base64,{base64.b64encode(data).decode()}"
    return (f'\n  <figure><img src="{uri}" alt="{html.escape(source.name)}" '
            f'style="max-width:100%;border-radius:8px">'
            f"<figcaption class=\"hint\">{html.escape(source.name)}</figcaption></figure>")


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


BULLET = re.compile(r"^\s*[-*•]\s+")


def inline(text: str) -> str:
    """One line of the note, escaped, with `code` and **bold** — the two the stylesheet draws."""
    said = html.escape(text.strip())
    said = re.sub(r"`([^`]+)`", r"<code>\1</code>", said)
    return re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", said)


def buildNote(note: str) -> str:
    """The note as the page's own prose, rather than one paragraph with its line breaks eaten.

    A blank line ends a paragraph, `## ` is a heading, `- `, `* ` or `• ` a bullet; any other line
    break stays one. The first paragraph is the lead.
    """
    parts: list[str] = []
    prose: list[str] = []
    items: list[str] = []

    def flush() -> None:
        if prose:
            parts.append("<p>" + "<br>".join(prose) + "</p>")
        if items:
            parts.append("<ul>" + "".join(f"<li>{item}</li>" for item in items) + "</ul>")
        prose.clear()
        items.clear()

    for line in note.strip().splitlines():
        if not line.strip():
            flush()
        elif line.lstrip().startswith("#"):
            flush()
            parts.append(f"<h2>{inline(line.lstrip().lstrip('#'))}</h2>")
        elif BULLET.match(line):
            if prose:
                flush()
            items.append(inline(BULLET.sub("", line, count=1)))
        else:
            if items:
                flush()
            prose.append(inline(line))
    flush()
    if parts and parts[0].startswith("<p>"):
        parts[0] = '<p class="lead">' + parts[0][3:]
    return "".join(f"\n  {part}" for part in parts)


def fillCommon(page: str, title: str, slug: str, note: str, images: list[str],
               decision: bool) -> str:
    """The four things every page has: its name, its id, its question and the words under it.

    A decision's page is those words and nothing else. The app draws its answer below the page and
    signs it with the phone's key; the template's own buttons could not answer one (`respond` is
    refused), so they were only a second, dead copy of the choices.
    """
    page = swap(page, r"<title>.*?</title>", f"<title>{html.escape(title)}</title>")
    page = swap(page, r'<p class="eyebrow" id="slug">.*?</p>',
                f'<p class="eyebrow" id="slug">{html.escape(slug)}</p>')
    words = f"<h1>{html.escape(title)}</h1>" + buildNote(note)
    words += "".join(embedImage(path) for path in images)
    if decision:
        page = swap(page, r"\n<script>.*?</script>", "")
        return swap(page, r"<h1>.*?</main>", f"{words}\n</main>")
    page = swap(page, r'\n\s*<p class="lead">.*?</p>', "")
    return swap(page, r"<h1>.*?</h1>", words)


def fillDecision(page: str, kind: str, options: list[str], action: str, expires: float) -> str:
    """The four `<meta>` tags that make a confirm, pick or text a decision (`docs/artifacts.md`).

    The choices are the labels the person sees: yes then no for a confirm, the rows of a pick, the
    field's label for a text — the same defaults the fill functions above draw.
    """
    choices = {"confirm": [options[0] if options else "Yes",
                           options[1] if len(options) > 1 else "No"],
               "pick": options, "text": [options[0] if options else "Answer"]}[kind]
    metas = "".join(
        f'<meta name="deckhand-{name}" content="{html.escape(value, quote=True)}">\n'
        for name, value in (("decision", kind), ("choices", json.dumps(choices, ensure_ascii=False)),
                            ("action", " ".join(action.split())),
                            ("expires", str(int(expires)))))
    return swap(page, r"</head>", f"{metas}</head>")


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
    parse.add_argument("--note", default="",
                       help="the words under the question. A blank line starts a paragraph, "
                            "'## ' a heading, '- ' a bullet; `code` and **bold** work")
    parse.add_argument("--image", action="append", default=[], metavar="PATH",
                       help="attach a picture. Pictures named in --title or --note are attached "
                            "without this")
    parse.add_argument("--option", action="append", default=[], metavar="TEXT",
                       help="pick: one row. confirm: the yes label, then the no label. "
                            "text: the field's label")
    parse.add_argument("--question", action="append", default=[], metavar="ID:TEXT",
                       help="aloud: one spoken question, keyed by id")
    parse.add_argument("--dir", default=".", metavar="DIR",
                       help="the session's own folder (default: here). Nothing walks upward "
                            "looking for one, so a slip written elsewhere is invisible")
    parse.add_argument("--session", default=os.environ.get("CLAUDE_CODE_SESSION_ID")
                       or os.environ.get("OPENCODE_SESSION_ID", ""),
                       metavar="ID",
                       help="whose slip this is (default: $CLAUDE_CODE_SESSION_ID, else OpenCode's "
                            "$OPENCODE_SESSION_ID). Empty writes "
                            "it to the folder, where every session working there sees it")
    parse.add_argument("--action", default="",
                       help="decisions: exactly what a yes allows, in one line. Required for a "
                            "confirm; a pick or text defaults to the question")
    parse.add_argument("--expires-hours", type=float, default=24.0, metavar="HOURS",
                       help="decisions: how long the question stands (default: 24)")
    parse.add_argument("--key", help="the dedup key: the slip id, overriding --slug and the title")
    said = parse.parse_args()

    slug = said.key or said.slug or buildSlug(said.title)
    if not SLUG.fullmatch(slug):
        sys.exit(f"slip.py: {slug!r} is not a slip id — letters, digits, - and _, one segment")
    # Loudly rather than flat: the daemon holds a session id to this same rule, so a slip filed
    # under one it refuses is one the phone never lists — the failure nobody notices.
    if said.session and not SLUG.fullmatch(said.session):
        sys.exit(f"slip.py: {said.session!r} is not a session id — one segment, no dot, no slash")
    if said.kind == "pick" and not said.option:
        sys.exit("slip.py: a pick needs at least one --option")
    if said.kind == "confirm" and not said.action.strip():
        sys.exit("slip.py: a confirm is a decision and needs --action: exactly what a yes allows")

    folder = Path(said.dir).expanduser().resolve() / ".deckhand" / "artifacts" / said.session
    where = folder / f"{slug}.html"
    # Asking an answered decision again must not wipe the person's answer: print it instead.
    if (kept := answer.answeredDecision(where)) is not None:
        print(json.dumps({"id": slug, "answered": True} | kept, ensure_ascii=False, indent=2))
        return 0

    images = said.image + [path for path in namedImages(said.title, said.note)
                           if path not in said.image]
    page = fillCommon((TEMPLATES / f"{said.kind}.html").read_text(), said.title, slug, said.note,
                      images, decision=said.kind != "aloud")
    if said.kind == "aloud":
        page = fillAloud(page, said.question)
    else:
        page = fillDecision(page, said.kind, said.option, said.action.strip() or said.title,
                            time.time() + said.expires_hours * 3600)

    folder.mkdir(parents=True, exist_ok=True)
    where.write_text(page)
    # An answer beside a page that has just been rewritten answers the old question, and the
    # phone would draw the slip as answered. Deleting it is how `docs/artifacts.md` says to ask
    # again, and rewriting a slip is asking again.
    (folder / f"{slug}.answer.json").unlink(missing_ok=True)
    print(where)
    return 0


if __name__ == "__main__":
    sys.exit(main())
