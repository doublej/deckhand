"""Which sessions have been messaging each other, for the overview to draw between them.

`edges.py` reads the receivers' transcripts and answers with the directed edges; `routes.py` is
the one endpoint over it. Read the top of `edges.py` before changing the parsing — the four ways
to get the envelope header quietly wrong are written out there, each measured against the real
messages on this Mac rather than assumed.

`routes` is never imported here, the same note `settings/` and `projects/` carry: it pulls in
FastAPI and the rest of the daemon, and `app.py` decides when that happens.
"""

from .edges import SessionLink, read_links

__all__ = ["SessionLink", "read_links"]
