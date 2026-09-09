"""Which filters this daemon has, and how the phone is told about them.

A register rather than a list kept somewhere: a filter declares itself in its own module on
import, so adding one touches one file. `known()` is the whole of what the phone learns about a
filter — name, title, summary, and the fields to draw — which is why the description in
`kinds.Filter` has to be good enough to render a control from. Nothing callable goes over the
wire; `apply` is the daemon's business.
"""

from __future__ import annotations

from dataclasses import asdict

from .kinds import Filter

_known: dict[str, Filter] = {}


def register(flt: Filter) -> Filter:
    """Declare a filter. Returns it, so a module can keep the name it registered."""
    _known[flt.name] = flt
    return flt


def get(name: str) -> Filter | None:
    return _known.get(name)


def known() -> list[dict]:
    """Every filter, described well enough for the phone to offer it without knowing what it is."""
    return [
        {
            "name": flt.name,
            "title": flt.title,
            "summary": flt.summary,
            "fields": [asdict(f) for f in flt.fields],
        }
        for flt in _known.values()
    ]
