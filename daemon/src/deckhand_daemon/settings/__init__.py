"""What the person has set this Mac to do.

Not `config.py`, which is how the daemon *runs* — where its data lives, which port, the token.
This is what the person has chosen: whether a folder is allowed to raise a Lock Screen card,
whether the idle check may chase a session in it, and what models the work there runs on.

Keyed by path throughout — except `aliases.py`, which is the one thing in here the person has
set for the whole Mac and not for a folder: a word comes back from utt wrong because of a voice,
which no folder has an opinion about. Read `wants.py` before changing anything here; the reason
there are two switches rather than four is written at the top of it, and the reason an alias is
not a `words` filter step is written at the top of `aliases.py`.

A note on the import shape, the same one `projects/` carries: `routes` is never imported here.
It pulls in FastAPI and the rest of the daemon, and `app.py` is the only thing that should be
deciding when that happens.
"""

from . import aliases
from .wants import SESSION_MODELS, SUMMARY_MODELS, Wants, document, resolved, save

__all__ = ["SESSION_MODELS", "SUMMARY_MODELS", "Wants", "aliases", "document", "resolved", "save"]
