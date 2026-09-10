"""The projects on this Mac, and starting a session in one of them.

`from .projects import catalog, start` is the whole of what the rest of the daemon needs: what
folders there are, whoever is keeping that list, and how a new session comes to exist in one.

The module is `sources` and the function it exports is `catalog`, which is not a spare distinction:
a package re-exporting a function under its own module's name shadows that module, and every
`from . import <that name>` afterwards silently hands back the function instead.

`routes` is deliberately not imported here. It reaches back out to `sessions`, and a package that
imported its own routes would close that loop — the same rule `filters/__init__.py` follows.
"""

from .sources import Project, catalog, forget
from .starting import start

__all__ = ["Project", "catalog", "forget", "start"]
