"""What a slip asks, read off its own page, so the phone can ask it without the page.

The page stays the whole truth of a slip. But the four kinds `slip.py` writes are mechanical, and
their markup says exactly what they ask — two buttons, a set of radio rows, one text field, or a
block of spoken questions — so reading that back is what lets the tray answer a yes without a web
view. A page that matches none of them is a `page`, and is opened as it always was. Unknown is
never guessed at: a wrong shape would send an answer the page itself would not have sent.
"""

from __future__ import annotations

import html
import json
import re
from typing import Any

BUTTON = r'<button id="{}"[^>]*>(.*?)</button>'
RADIO = re.compile(r'<input[^>]*type="radio"[^>]*value="([^"]*)"')
INPUT = re.compile(r"<input\b[^>]*>")
LABEL = re.compile(r'<label class="eyebrow" for="name">(.*?)</label>', re.DOTALL)
ALOUD = 'id="deckhand-aloud"'
#: How much of an answer an update row carries. The answer file holds all of it.
BRIEF = 120


def ask(page: str | None) -> dict:
    """`{"kind": "confirm", "accept", "decline"}`, `{"kind": "pick", "options", "other"}`,
    `{"kind": "text", "label"}`, `{"kind": "aloud"}` or `{"kind": "page"}`.

    In that order, and aloud first: its page has a Send button and no radios, and must never read
    as anything a single tap could answer. Each kind is also held to the *only* inputs its
    template has — a form has radio rows too, and answering it as a pick would send half of it.
    """
    if not page:
        return {"kind": "page"}
    if ALOUD in page:
        return {"kind": "aloud"}
    inputs = INPUT.findall(page)
    others = [tag for tag in inputs if 'type="radio"' not in tag]
    yes, no = (_words(re.search(BUTTON.format(which), page, re.DOTALL)) for which in ("yes", "no"))
    if yes and no and all('id="note"' in tag for tag in inputs):
        return {"kind": "confirm", "accept": yes, "decline": no}
    values = [html.unescape(value) for value in RADIO.findall(page)]
    options = [value for value in values if value]
    if options and all('id="other"' in tag for tag in others):
        return {"kind": "pick", "options": options, "other": "" in values}
    if len(inputs) == 1 and 'id="name"' in inputs[0] and 'type="text"' in inputs[0]:
        return {"kind": "text", "label": _words(LABEL.search(page)) or "Answer"}
    return {"kind": "page"}


def said(value: Any, shape: dict) -> str:
    """An answer in the words the person saw: a confirm's `true` is its own button's label."""
    if isinstance(value, dict) and "answer" in value:
        value = value["answer"]
    if isinstance(value, bool):
        picked = shape.get("accept" if value else "decline") if shape.get("kind") == "confirm" else ""
        found = picked or ("Yes" if value else "No")
    elif isinstance(value, str):
        found = value
    elif isinstance(value, dict):
        found = " · ".join(str(part) for part in value.values())
    else:
        found = json.dumps(value, ensure_ascii=False)
    found = " ".join(found.split())
    return found if len(found) <= BRIEF else found[:BRIEF - 1].rstrip() + "…"


def _words(found: re.Match | None) -> str:
    """A button's or a label's text: tags out, entities read, whitespace folded."""
    if found is None:
        return ""
    return " ".join(html.unescape(re.sub(r"<[^>]+>", "", found.group(1))).split())
