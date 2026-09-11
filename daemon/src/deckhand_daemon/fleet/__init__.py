"""The machines this daemon can see, and — later — the link to the ones that are not this Mac.

Today this is the registry only: atlas says which machines exist, and `here()` is what stamps
every session with the one it runs on. The supervised ssh forward, the proxy and the merged
listing are `docs/network.md` phase 2 and land beside this.
"""

from .registry import Machine, here, machines, primary

__all__ = ["Machine", "here", "machines", "primary"]
