"""The machines this daemon can see, and the live link to the ones that are not this Mac.

`registry.py` reads atlas's list of machines. `link.py` is one ssh process per remote machine,
forwarding a port and running the hand behind it. `proxy.py` calls a hand and keeps its link
honest. `merge.py` makes one listing out of several. `hand.py` is what runs on the far end.

Nothing here is reachable from the LAN: a hand binds loopback and the only way to it is the ssh
forward. `docs/network.md` is the whole design and the reasoning behind each refusal.
"""

from .link import stop_all
from .merge import links_of, listings, machines, owner, warm
from .registry import Machine, here, primary
from .registry import machines as known

__all__ = [
    "Machine", "here", "known", "links_of", "listings", "machines", "owner", "primary",
    "stop_all", "warm",
]
