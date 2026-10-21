#!/usr/bin/env python3
"""Every demo page parses, names itself, answers through the app, and stays inside the CSP.

The viewer injects `default-src 'none'` with inline style and script only, so a page that
reaches for anything off the device fails **silently** on the phone: no error, no empty box,
nothing in the UI saying why. This is where that gets said instead. Run it from anywhere:

    python3 demos/check.py
"""

import sys
from html.parser import HTMLParser
from pathlib import Path

VOID = {"area", "base", "br", "col", "embed", "hr", "img",
        "input", "link", "meta", "source", "track", "wbr"}

# The first four are the CSP's own boundary. The rest are the ways a page reaches past it that
# reading for those four would miss — a relative src is as dead as a CDN one under `'none'`.
BANNED = ("http://", "https://", "fetch(", "<form",
          "<link", "<iframe", "<script src", "XMLHttpRequest", "@import")


class Page(HTMLParser):
    """Balance, and the title. Enough of a parse that a page that will not render fails here."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[tuple[str, int]] = []
        self.faults: list[str] = []
        self.title = ""
        self._titling = False

    def handle_starttag(self, tag: str, attrs: object) -> None:
        if tag in VOID:
            return
        self.stack.append((tag, self.getpos()[0]))
        self._titling = self._titling or tag == "title"

    def handle_endtag(self, tag: str) -> None:
        if tag in VOID:
            return
        if tag == "title":
            self._titling = False
        if not self.stack:
            self.faults.append(f"line {self.getpos()[0]}: </{tag}> closes nothing")
            return
        opened, line = self.stack.pop()
        if opened != tag:
            self.faults.append(
                f"line {self.getpos()[0]}: </{tag}> closes <{opened}> opened on line {line}"
            )

    def handle_data(self, data: str) -> None:
        if self._titling:
            self.title += data.strip()


def check(path: Path) -> tuple[str, list[str]]:
    text = path.read_text(encoding="utf-8")
    page = Page()
    page.feed(text)
    page.close()

    faults = list(page.faults)
    faults += [f"<{tag}> opened on line {line} and never closed" for tag, line in page.stack]
    if not page.title:
        faults.append("no <title> — that is where the artifact's name comes from")
    # A decision is answered by the app's own signed controls, never by the page (`artifacts.md`).
    if "window.deckhand.respond" not in text and 'name="deckhand-decision"' not in text:
        faults.append("never calls window.deckhand.respond — it cannot answer")
    faults += [f"contains {banned!r}, which the CSP blocks" for banned in BANNED if banned in text]
    return page.title, faults


def main() -> int:
    demos = sorted(Path(__file__).resolve().parent.glob("*.html"))
    if not demos:
        print("no demo pages found", file=sys.stderr)
        return 1

    failing = 0
    for path in demos:
        title, faults = check(path)
        print(f"{path.name}: {'FAIL' if faults else 'ok'}  {title}")
        for fault in faults:
            print(f"    {fault}")
        failing += bool(faults)

    print(f"\n{len(demos)} pages, {failing} failing")
    return 1 if failing else 0


if __name__ == "__main__":
    sys.exit(main())
