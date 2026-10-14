"""The manager: one Claude session inside the daemon that the phone talks to.

Everything else in this repo is the person speaking *to* a session. This is the person speaking
to something that speaks to sessions — a panel on the phone, a conversation the daemon keeps, and
a small facade of tools over this daemon's own modules.

```
talk.py     # the conversation on disk: numbered entries, and the SDK thread behind them
tools.py    # what the manager may read, and how a session is named to it
doing.py    # what it may change, the three things it may not touch, and the tool server
agent.py    # the run itself: one session held open, so other sessions can message it
routes.py   # the four endpoints under /manager
```

**Read `doing.py`'s docstring before adding a tool.** The line it draws — the manager never types
into a pane — is the same authority invariant the delivery routes answer, and it is what decides
whether a new verb belongs here at all.
"""

from . import agent, doing, routes, talk, tools

__all__ = ["agent", "doing", "routes", "talk", "tools"]
