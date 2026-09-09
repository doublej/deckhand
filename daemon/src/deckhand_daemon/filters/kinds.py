"""The shapes a prompt filter is written against. Nothing here does anything.

The idea is one line long: what a person says to a session is not always what should reach it.
It might need a word swapped, a language changed, a check against what is already logged, a note
attached — or it might need stopping. So the words go through a chain of small steps on the way
in, each of which may rewrite them, say something about them, or refuse them.

Everything in here is deliberately dull. A filter is a function and a bit of description; the
description is what lets the phone offer it without knowing what it does. Keep it that way: the
moment a filter needs a special case in the runner, it is not a filter.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field


@dataclass(slots=True)
class Prompt:
    """What is about to be said to a session, and what a filter may judge it by."""

    text: str
    session_id: str
    session_name: str = ""
    cwd: str = ""
    route: str = "auto"
    images: list[str] = field(default_factory=list)
    # How the words arrived: "typed", "spoken". A filter may reasonably care — a slip of the
    # tongue and a slip of the finger are not the same mistake.
    source: str = "typed"


@dataclass(slots=True)
class Verdict:
    """One step's answer.

    Three things it can do and they compose: leave the words alone (`text` is None), change them,
    and say something about what it did. `stop` is the fourth, and it is the only one that ends
    the chain — a filter that stops something must say why, because a message that vanishes
    without a reason is the bug this whole app has been chasing all week.
    """

    text: str | None = None
    note: str = ""
    stop: bool = False


@dataclass(slots=True)
class Outcome:
    """What the whole chain decided, and everything the person should be told about it."""

    text: str
    notes: list[str] = field(default_factory=list)
    # The name of the step that refused it, when one did.
    stopped_by: str | None = None
    # A refusal's `note`, and the only place it goes: the runner does not also add it to `notes`,
    # or the phone would draw the same sentence twice in two different voices. So `notes` is what
    # the chain did on the way past and `reason` is why it ended — never the same words in both.
    # A filter that stops without a note gets one written for it rather than vanishing silently.
    reason: str = ""

    @property
    def delivered(self) -> bool:
        return self.stopped_by is None


@dataclass(slots=True)
class Field:
    """One setting a filter takes, described well enough for the phone to draw a control."""

    key: str
    label: str
    # "text" | "bool" | "number" | "pairs" — pairs is a list of [from, to], which is the shape
    # a replacement list wants and a plain text box cannot express.
    kind: str = "text"
    # Never a list or a dict: `settings()` below hands this out by reference, so a mutable default
    # is one object shared by every prompt this daemon ever filters, and a filter that edits its
    # own settings in place would rewrite the declaration for all of them. An empty list of pairs
    # is `()`, which cannot be mutated in the first place and still goes over the wire as `[]`.
    default: object = ""
    hint: str = ""


@dataclass(slots=True)
class Filter:
    """A step, and enough about it that nothing else has to know what it is."""

    name: str
    title: str
    summary: str
    fields: list[Field] = field(default_factory=list)
    # Sync or async: the runner awaits whatever comes back. A filter that asks a model is the
    # whole reason the async door is open.
    #
    # Optional, so a Filter can be registered as a description with nothing behind it yet — which
    # means the runner has to treat `apply is None` as a step it cannot run and say so, exactly as
    # it treats a saved step naming a filter this Mac no longer has.
    apply: Callable[[Prompt, dict], Verdict | Awaitable[Verdict]] | None = None

    def settings(self, given: dict | None = None) -> dict:
        """Its defaults, with whatever the person set on top."""
        merged = {f.key: f.default for f in self.fields}
        merged.update(given or {})
        return merged
