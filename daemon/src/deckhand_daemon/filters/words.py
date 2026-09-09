"""Swap words the dictation keeps getting wrong.

The first filter, and deliberately the dullest one. utt's own hint list already catches a word
misheard as a near-miss of itself ("cockwheel" → "cogwheel"), but it cannot touch an ordinary
word heard as another ordinary word, and the same handful go wrong every day. This can, because
it is told the pairs rather than guessing at them.

Whole words only, case ignored on the way in and taken as written on the way out: what was typed
into the settings is what appears, whether the person said it mid-sentence or shouted it.
"""

from __future__ import annotations

import re

from .kinds import Field, Filter, Prompt, Verdict
from .registry import register


def _swap(prompt: Prompt, settings: dict) -> Verdict:
    text, notes = prompt.text, []
    for pair in settings.get("pairs") or []:
        if not isinstance(pair, (list, tuple)) or len(pair) != 2:
            continue
        wrong, right = str(pair[0]).strip(), str(pair[1])
        if not wrong:
            continue
        # A function rather than a replacement string: `right` is a person's words, and a
        # backslash in it would otherwise be read as a group reference.
        text, hits = re.subn(_whole(wrong), lambda _m, r=right: r, text, flags=re.IGNORECASE)
        if hits:
            notes.append(f'swapped "{wrong}" for "{right}"')
    # `text` unchanged is None, not the same string again: a filter that did nothing says so.
    return Verdict(text=text if notes else None, note="; ".join(notes))


def _whole(word: str) -> str:
    r"""A match that cannot be half of something else, whatever the word ends in.

    `\b` is wrong here: it is defined against word characters, so a pair ending in punctuation
    ("c++") would happily match at the front of the next word. These two guards hold for any
    edge character, and a pair with a space in it ("deck hand") works the same way.
    """
    return rf"(?<!\w){re.escape(word)}(?!\w)"


WORDS = register(
    Filter(
        name="words",
        title="Word replacement",
        summary="Swap words dictation keeps getting wrong, before they reach the session.",
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
