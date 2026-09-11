"""Swap words the dictation keeps getting wrong, in this one terminal.

The first filter, and deliberately the dullest one. utt's own hint list already catches a word
misheard as a near-miss of itself ("cockwheel" → "cogwheel"), but it cannot touch an ordinary
word heard as another ordinary word, and the same handful go wrong every day. This can, because
it is told the pairs rather than guessing at them.

**A word that goes wrong everywhere is an alias, not a step in this chain.** `settings/aliases.py`
holds the Mac-wide list and runs before the chain does, so it also reaches the manager, which has
no chain at all. This filter is for the pairs somebody wants in one project and nowhere else —
a name, a piece of jargon, a word that only means something here.

The swap itself lives in `aliases.swap`, which is where the whole-word rule is written down once:
whole words only, case ignored on the way in and taken as written on the way out.
"""

from __future__ import annotations

from ..settings import aliases
from .kinds import Field, Filter, Prompt, Verdict
from .registry import register


def _swap(prompt: Prompt, settings: dict) -> Verdict:
    text, notes = aliases.swap(prompt.text, settings.get("pairs"))
    # `text` unchanged is None, not the same string again: a filter that did nothing says so.
    return Verdict(text=text if notes else None, note="; ".join(notes))


WORDS = register(
    Filter(
        name="words",
        title="Word replacement",
        summary="Swap words in this terminal only. A word that goes wrong everywhere is an alias.",
        fields=[
            Field(
                key="pairs",
                label="Replacements",
                kind="pairs",
                default=(),
                hint='What was heard, and what you meant: "deck hand" becomes "deckhand"',
            )
        ],
        apply=_swap,
    )
)
