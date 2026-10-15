"""What one session's standing orders are, and how they get in front of a message.

A file per session beside `tasks/` and `briefings/`, and `carry` is the only thing that reads it
for delivery. Everything about *when* it is carried lives in `saying.py`, which is the one place a
prompt from the person comes through.

**Empty is nothing, and nothing means the same object back.** A session with no orders — never
written, or written and cleared — gets `carry` handing back the very string it was passed. Not an
equal string: the same one. That is the whole guarantee this module owes the rest of the daemon,
because the alternative is a blank line or a stray header quietly riding on every prompt anybody
ever sends any session, and nothing on the phone would show it.

**The words are the person's and they stay the person's.** They go in front of the message they
ride on, inside the same delivery, so they carry exactly the authority of that message and never a
scrap more: typed into the pane they arrive as JJ, down the peer socket they arrive wrapped in
"another Claude session sent this" like everything else on that route. There is no route on which
standing orders can outrank the prompt they are attached to, and there must never be one.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

from .. import prompts
from ..config import data_dir
from ..log import log

ORDERS = prompts.load("orders")
# How much a person may put in the field. Read off the prompt file, where the reason for the
# number is written: these characters are spent again on every single turn.
LIMIT = int(ORDERS.settings["limit"])


def path(session_id: str) -> Path:
    folder = data_dir() / "orders"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f"{session_id}.json"


def load(session_id: str) -> str:
    """This session's standing orders, or "" when it has never been given any."""
    try:
        return str(json.loads(path(session_id).read_text()).get("text", ""))
    except FileNotFoundError:
        return ""
    except (OSError, json.JSONDecodeError, AttributeError) as error:
        log.warning("could not read the orders for %s: %s", session_id, error)
        return ""


def save(session_id: str, text: str) -> str:
    """Store them and answer with what was *stored*, which is not always what was sent.

    Clearing the field is a save of nothing rather than a delete: the file staying there with an
    empty string in it is what makes "these orders were cleared" and "this session never had any"
    the same thing to every reader, which they are.
    """
    wanted = clean(text)
    path(session_id).write_text(json.dumps({"text": wanted, "changed": time.time()}))
    log.info("standing orders for %s: %d chars", session_id, len(wanted))
    return wanted


def clean(text: str) -> str:
    """One person's paragraph, clamped, with nothing in it that a terminal would act on.

    Newlines survive because the field is prose the person reads back on the phone; every other
    unprintable character goes, for the reason `deliver.clean_name` gives — this ends up typed
    into a live tmux pane, and an escape sequence pasted into the box would be keystrokes rather
    than words. `deliver` flattens the newlines again on the way out; it does not filter.
    """
    kept = "".join(c for c in text if c.isprintable() or c == "\n")
    return kept.strip()[:LIMIT]


def carry(session_id: str, text: str) -> str:
    """The message with this session's standing orders in front of it. Unchanged when it has none.

    In front rather than behind, and the argument is what a long dictated ramble does to each. The
    orders are the constraints; the message is the thing being asked for. Put them last and the
    final words of every prompt are the same paragraph the session has already read forty times,
    with the actual request buried above it — so the model answers the boilerplate. Put them first
    and the prompt ends where it should, on what the person just said, which is exactly the shape
    a system prompt has for exactly this reason.

    On every message rather than once, and the daemon deliberately does not try to be clever about
    it. It does not own the session's context: a `/clear`, a compact it never saw, or a queued
    prompt dropped on a restart all make "I have already said this" false, and each of them fails
    the same silent way — the orders quietly stop applying and nothing anywhere says so. The cost
    of the honest version is bounded and visible instead: `LIMIT` characters, in the person's own
    words, on the same screen they wrote them.
    """
    orders = load(session_id)
    if not orders:
        return text
    return ORDERS.filled(orders=orders, prompt=text)
