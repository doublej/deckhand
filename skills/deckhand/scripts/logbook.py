#!/usr/bin/env python3
"""Keep a logbook slip — the page on the phone that says where a long job has got to.

A question slip asks and waits. This one does not ask: it is the running account of a job too
long to say in a sentence, locked on the phone so the person can look at it whenever they like
without asking how it is going. Every command below rewrites the whole page from a small state
file beside it, which is what keeps it cheap — a logbook that costs a page rewrite per entry
stops getting entries by the third one.

    logbook.py start "Moving the reader onto the new store" --standing "Porting, then a cutover."
    logbook.py add done "Read every caller" "Nine, two of them in the manager."
    logbook.py add blocked "Export needs an account" "No Apple token on this Mac."
    logbook.py standing "Everything but the cutover is done."
    logbook.py finish "Cut over at 16:40, no session lost its place."

Prints the path it wrote, every time.

**A logbook is flat by default, where a question slip is the session's own.** That is the one
deliberate difference between this and `slip.py`, and it is the whole point: a question belongs
to the session that asked it because the answer has to come back there, while a long job outlives
the session working it — compacted, cleared, restarted, handed over. Flat is the folder's scope,
so any session in this folder appends to the same logbook by running the same command, and the
phone marks the row `project`. Pass `--session "$CLAUDE_CODE_SESSION_ID"` to pin one to a single
session instead.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import sys
from datetime import datetime
from pathlib import Path

# `slip.py` is next door in this same folder, so `sys.path[0]` finds it wherever this is run
# from, symlink included. Sharing rather than copying: one rule for what a slug may be, one
# template loader, one set of anchors into the demo pages.
from slip import SLUG, TEMPLATES, swap

# How many entries the page draws. A phone is a phone: past a dozen rows nobody reads the list,
# they read the standing line at the top and scroll no further. The rest are not lost — they stay
# in the state file, which is the durable half, and the page says how many it is not showing.
SHOWN = 12
# A step is a row heading and a `said` is the line under it. Refused rather than truncated: an
# agent that pasted a diff in here wants to know, and a silently cut sentence is a logbook that
# lies about what it recorded.
STEP = 80
SAID = 300
STATES = ("done", "doing", "blocked", "note")


def now() -> str:
    """Local time with its offset, so a logbook read tomorrow still says which day that was."""
    return datetime.now().astimezone().isoformat(timespec="seconds")


def writeAtomically(path: Path, text: str) -> None:
    """Write in one move, because both of these are read while they are being written.

    The page is refetched by the phone whenever the slip is opened and the daemon rereads it to
    list the slip, and unlike a question page this one is rewritten on every entry — so a plain
    write has a window where the phone gets half a page. `os.replace` on the same directory is
    atomic: the reader gets the old file or the new one and never part of either.
    """
    near = path.with_name(path.name + ".writing")
    near.write_text(text)
    os.replace(near, path)


def store(said: argparse.Namespace) -> Path:
    """The folder this logbook lives in, made if it is not there yet.

    The session id is a folder name here and a path segment in the daemon's own URL, so it is
    held to the same rule an artifact id is: one segment, no dot and no separator. Loudly,
    because a logbook filed under an id the daemon refuses is one the phone never lists.
    """
    if said.session and not SLUG.fullmatch(said.session):
        sys.exit(f"logbook.py: {said.session!r} is not a session id — one segment, no dot, no slash")
    if not SLUG.fullmatch(said.slug):
        sys.exit(f"logbook.py: {said.slug!r} is not a slip id — letters, digits, - and _")
    folder = Path(said.dir).expanduser().resolve() / ".deckhand" / "artifacts" / said.session
    folder.mkdir(parents=True, exist_ok=True)
    return folder


def read(folder: Path, slug: str) -> dict:
    """The logbook's own state, or the one sentence that says how to start one.

    It sits beside the page rather than in a scratch folder, and that is what makes a logbook a
    thing the *folder* has rather than a thing one session remembers: a second session appends by
    running the same command in the same directory, with nothing to find and nothing to be told.
    """
    where = folder / f"{slug}.log.json"
    if not where.is_file():
        sys.exit(f"logbook.py: no logbook at {where} — start one with "
                 f'`logbook.py start "<what the job is>"`')
    return json.loads(where.read_text())


def write(folder: Path, book: dict) -> Path:
    """Save the state and rewrite the page from it. The only way either of them changes."""
    book["updated"] = now()
    writeAtomically(folder / f"{book['slug']}.log.json",
                    json.dumps(book, indent=2, ensure_ascii=False) + "\n")
    page = folder / f"{book['slug']}.html"
    writeAtomically(page, render(book))
    # No `unlink` of the answer file here, and that is the difference from `slip.py`: rewriting a
    # question is asking it again, so its old answer has to go, while rewriting a logbook is the
    # same page saying more. A note the person left an hour ago survives every entry after it.
    return page


def render(book: dict) -> str:
    """The demo page, filled in. It renders itself from the block, so this writes one block.

    `demos/logbook.html` is the only copy of the markup — the same arrangement `aloud.html` has
    and for the same reason: a page built by string concatenation here would drift from the page
    `just demo-check` actually gates, and the drift would show up on someone's phone.
    """
    entries = book["entries"]
    block = {
        "finished": book["finished"],
        "updated": book["updated"],
        "earlier": max(0, len(entries) - SHOWN),
        # Over every entry rather than the shown ones: the tally is what the standing line leans
        # on, and "3 done" under a job with fifteen done steps is worse than no tally at all.
        "counts": {state: sum(entry["state"] == state for entry in entries) for state in STATES},
        "entries": entries[-SHOWN:],
    }
    title = html.escape(book["title"])
    page = (TEMPLATES / "logbook.html").read_text()
    page = swap(page, r"<title>.*?</title>", f"<title>{title}</title>")
    page = swap(page, r'<p class="eyebrow" id="slug">.*?</p>',
                f'<p class="eyebrow" id="slug">{html.escape(book["slug"])}</p>')
    page = swap(page, r"<h1>.*?</h1>", f"<h1>{title}</h1>")
    page = swap(page, r'<p class="lead">.*?</p>',
                f'<p class="lead">{html.escape(book["standing"])}</p>')
    # The comment explains the block to whoever opens the demo; on a phone it is an instruction
    # for an agent sitting in the middle of a page written for a person.
    page = swap(page, r"\n\s*<!--\s*WRITTEN BY logbook\.py.*?-->", "")
    # `</` closed as `<\/` so a sentence containing `</script>` cannot end the block early. Still
    # ordinary JSON — `\/` is a valid escape — so the page parses it unchanged.
    dumped = json.dumps(block, indent=2, ensure_ascii=False).replace("</", "<\\/")
    return swap(page, r'<script type="application/json" id="deckhand-logbook">.*?</script>',
                f'<script type="application/json" id="deckhand-logbook">\n{dumped}\n  </script>')


def short(what: str, text: str, cap: int) -> str:
    """A line, or the reason it is not one."""
    text = " ".join(text.split())
    if len(text) > cap:
        sys.exit(f"logbook.py: that {what} is {len(text)} characters and the cap is {cap} — "
                 "a logbook entry is a line read at arm's length, not a paragraph")
    return text


def start(said: argparse.Namespace, folder: Path) -> Path:
    """Begin one, or refuse to stand on an unfinished one.

    Refusing matters here because `logbook` is the default slug: two jobs running in one folder
    would otherwise have the second one silently wipe the first one's history, and the first
    session would go on appending to a book whose earlier half is gone. A finished logbook is
    fair game — that job is over.
    """
    where = folder / f"{said.slug}.log.json"
    if where.is_file() and not json.loads(where.read_text())["finished"]:
        sys.exit(f"logbook.py: {where} is already going — append to it with `logbook.py add`, "
                 "finish it, or start this one under its own --slug")
    return write(folder, {
        "slug": said.slug,
        "title": short("title", said.title, STEP),
        "standing": short("standing line", said.standing, SAID),
        "finished": False,
        "started": now(),
        "entries": [],
    })


def add(said: argparse.Namespace, folder: Path) -> Path:
    """One more thing that happened. The command this whole design exists to make cheap."""
    book = read(folder, said.slug)
    book["entries"].append({
        "state": said.state,
        "step": short("step", said.step, STEP),
        "said": short("line", said.said, SAID),
        "at": now(),
    })
    if said.standing:
        book["standing"] = short("standing line", said.standing, SAID)
    return write(folder, book)


def main() -> int:
    parse = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    shared = argparse.ArgumentParser(add_help=False)
    shared.add_argument("--slug", default="logbook", metavar="ID",
                        help="which logbook (default: logbook). A folder running two jobs at "
                             "once gives the second one its own")
    shared.add_argument("--dir", default=".", metavar="DIR",
                        help="the folder the job is in (default: here). Nothing walks upward "
                             "looking for one, so a logbook written elsewhere is invisible")
    shared.add_argument("--session", default="", metavar="ID",
                        help="pin it to one session (default: none, so it belongs to the folder "
                             "and any session working there appends to it)")
    doing = parse.add_subparsers(dest="doing", required=True)

    begin = doing.add_parser("start", parents=[shared], help="begin a logbook")
    begin.add_argument("title", help="what the job is — the slip's name on the phone")
    begin.add_argument("--standing", default="Just started.",
                       help="the line at the top that answers 'where is this now'")

    entry = doing.add_parser("add", parents=[shared], help="append one thing that happened")
    entry.add_argument("state", choices=STATES)
    entry.add_argument("step", help="what it was, as a heading")
    entry.add_argument("said", nargs="?", default="", help="what happened, in one line")
    entry.add_argument("--standing", default="", help="update the standing line in the same move")

    stands = doing.add_parser("standing", parents=[shared],
                              help="rewrite the line at the top, changing nothing else")
    stands.add_argument("text")

    over = doing.add_parser("finish", parents=[shared], help="the job is over")
    over.add_argument("text", nargs="?", default="", help="the standing line to leave it on")

    said = parse.parse_args()
    folder = store(said)
    if said.doing == "start":
        page = start(said, folder)
    elif said.doing == "add":
        page = add(said, folder)
    else:
        book = read(folder, said.slug)
        if said.doing == "finish":
            book["finished"] = True
        if said.text or said.doing == "standing":
            book["standing"] = short("standing line", said.text, SAID)
        page = write(folder, book)
    print(page)
    return 0


if __name__ == "__main__":
    sys.exit(main())
