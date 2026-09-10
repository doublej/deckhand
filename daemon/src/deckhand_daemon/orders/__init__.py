"""Standing orders: what one session is to be reminded of on every message it is sent.

The other three things the Mac keeps per session are things the *Mac* worked out — the briefing a
model wrote, the asks a model filed, the queue it read out of a transcript. This is the one the
person typed, and the only one that goes back out again.

Keyed by session id and not by folder, which is the opposite of `settings/`. That is deliberate
and it is the same call JJ made about slips: what you want a session reminded of is a property of
the argument you are having with it this afternoon, not of the folder it happens to be running in.
Two sessions in one repo doing two jobs would otherwise share one paragraph and both be wrong. The
cost is honest and known — a session id is new on every restart, so orders last as long as the
terminal does, exactly like the tasks and the briefings filed under the same key.

`kept.py` is the store and the one function that puts them in front of a message; `routes.py` is
the two endpoints over it. `routes` is never imported here, the note `settings/`, `links/` and
`projects/` all carry: it pulls in FastAPI and the rest of the daemon, and `app.py` is the only
thing that should be deciding when that happens.
"""

from .kept import LIMIT, carry, clean, load, path, save

__all__ = ["LIMIT", "carry", "clean", "load", "path", "save"]
