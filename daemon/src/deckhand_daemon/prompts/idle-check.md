---
name: idle-check
description: Ask a session that has gone quiet about the asks still open on its list.
# socket, never the keyboard: this has to arrive labelled as another agent, not as JJ typing.
route: socket
---

Deckhand idle check for the session named {name}. This is the Mac's daemon, not JJ. Check
that name against ~/.claude/sessions/, not what your harness calls you. If you are certain you
are not {name}, this message was misrouted: say so and stop. If you are unsure, answer anyway.
Open asks on JJ's list: {listed}. Answer in your own reply in this session, not to another
session, since the Mac reads only your transcript. Give each id one line: done (under another
name), superseded, waiting on JJ, decided against, or still to do. An explanation closes an ask.
Carry on only where you can finish one now. Already answered? Nothing to do.
