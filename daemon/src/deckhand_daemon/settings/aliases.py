"""Words this Mac always mishears, and what they were meant to be.

An alias is one pair: what came back from utt, and what was actually said. It is Mac-wide on
purpose, and that is the whole design decision here — a word comes back wrong because of a voice
and a model, never because of which terminal it was said at. The two nearer-looking homes are
both wrong for that reason:

- **The `words` filter** does this same swap already, and its list belongs to one *terminal*
  (`filters/config.py` keys a chain by session name). Fixing "deck hand" in one pane would leave
  it broken in every other, and `POST /manager/audio` runs no chain at all — the manager's own
  staging card would never see the correction. The filter stays as it is for what it is good at:
  a swap somebody wants in one project and nowhere else.
- **utt's own replacement list** cannot be reached from here in any way that works.
  `AppFeature.applySystemPreferences` builds the transcriber it hands `extensionJobs.apply` inside
  a closure capturing a *snapshot* of utt's settings, and its only five callers are in-process.
  A rule written into utt's `settings.json` from this side therefore reaches utt's UI and its own
  hotkey dictation at once, and Deckhand's clips not until utt is relaunched — which is the exact
  opposite of the thing being asked for.

So the swap happens here, the moment a clip comes back, before the filter chain or the manager
sees the words. The right-hand side also goes into `transcribe.hints_for`: an alias says what the
word should have been, which is the best hint there is for not mishearing it next time.

Whole words only, case ignored on the way in and taken as written on the way out. `swap` is where
that rule lives for the whole daemon — `filters/words.py` runs it too rather than keeping a second
copy of the regex.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from ..config import data_dir
from ..log import log


def path() -> Path:
    return data_dir() / "aliases.json"


def load() -> list[list[str]]:
    """Every alias on this Mac. A list that cannot be read is no aliases rather than an error:
    a half-written file must not be able to stop somebody speaking to a session."""
    try:
        saved = json.loads(path().read_text())
    except FileNotFoundError:
        return []
    except (OSError, json.JSONDecodeError) as broken:
        log.warning("aliases.json is unreadable, so nothing is swapped: %s", broken)
        return []
    return _kept(saved.get("aliases") if isinstance(saved, dict) else saved)


def save(sent: object) -> list[list[str]]:
    """Replace the list, and hand back exactly what was written."""
    kept = _kept(sent)
    path().write_text(json.dumps({"aliases": kept}, indent=2))
    return kept


def applied(text: str) -> tuple[str, list[str]]:
    """The words with every alias applied, and a line per alias that actually fired."""
    return swap(text, load())


def spoken() -> list[str]:
    """The right-hand words, for the hints a clip is transcribed with."""
    return [meant for _, meant in load() if meant]


def swap(text: str, pairs: object) -> tuple[str, list[str]]:
    """The swap itself, shared with the `words` filter.

    Whole words only, whatever the pair ends in, and a pair with an empty left side is skipped:
    a blank row in an editor is not an instruction to rewrite every gap in the sentence.
    """
    notes = []
    for heard, meant in _pairs(pairs):
        # A function rather than a replacement string: `meant` is a person's words, and a
        # backslash in it would otherwise be read as a group reference.
        text, hits = re.subn(_whole(heard), lambda _m, r=meant: r, text, flags=re.IGNORECASE)
        if hits:
            notes.append(f'swapped "{heard}" for "{meant}"')
    return text, notes


def _whole(word: str) -> str:
    r"""A match that cannot be half of something else, whatever the word ends in.

    `\b` is wrong here: it is defined against word characters, so a pair ending in punctuation
    ("c++") would happily match at the front of the next word. These two guards hold for any
    edge character, and a pair with a space in it ("deck hand") works the same way.
    """
    return rf"(?<!\w){re.escape(word)}(?!\w)"


def _pairs(sent: object) -> list[list[str]]:
    """Whatever was handed over, as rows of two strings with a left side worth matching."""
    if not isinstance(sent, (list, tuple)):
        return []
    rows = []
    for pair in sent:
        if not isinstance(pair, (list, tuple)) or len(pair) != 2:
            continue
        heard, meant = str(pair[0]).strip(), str(pair[1]).strip()
        if heard:
            rows.append([heard, meant])
    return rows


def _kept(sent: object) -> list[list[str]]:
    """The stored list: rows of two, and one row per word.

    Keyed on the heard side case-folded, because that is what the match is keyed on — two rows
    for "deck hand" and "Deck Hand" are one alias written twice, and the second could never fire
    anyway. The later one wins and keeps the earlier one's place, so correcting an alias does not
    move it to the bottom of somebody's list.
    """
    rows: dict[str, list[str]] = {}
    for heard, meant in _pairs(sent):
        rows[heard.casefold()] = [heard, meant]
    return list(rows.values())
