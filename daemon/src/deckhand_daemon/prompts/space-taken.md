---
name: space-taken
description: Tell a session the person took a page or window away from beside it in the headset.
# socket, never the keyboard: this is the daemon speaking, not JJ typing.
route: socket
# What became of it, filled in as {how}. {name} is the session he handed it to.
how:
  closed: he closed it
  handed: he handed it to the session {name}
  loose: he moved it away, and it stands beside no session now
---

Deckhand, the Mac's daemon, not JJ: in his headset JJ has taken {what} (plane {id}) away from
beside your terminal: {how}. What he says is no longer about that page. If you still need it
there, ask him rather than reopening it yourself. No reply needed.
