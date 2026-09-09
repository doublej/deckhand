"""The chain a prompt goes through on its way into a session.

`from .filters import run, known, load, save` is the whole of what the rest of the daemon needs:
what the words became, what filters exist, and what the person has them doing. Nothing outside
this package should have to name a module inside it.

Importing this is also what fills the register — each built-in filter declares itself in its own
module, so the import list below is the only thing that has to change to add one.
"""

from . import crafting, words  # noqa: F401  -- imported for the register they fill on the way past
from .config import load, path, save
from .kinds import Field, Filter, Outcome, Prompt, Verdict
from .registry import known, register
from .runner import run

__all__ = [
    "Field",
    "Filter",
    "Outcome",
    "Prompt",
    "Verdict",
    "known",
    "load",
    "path",
    "register",
    "run",
    "save",
]
