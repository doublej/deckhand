---
name: idle-check
description: Ask a session that has gone quiet about the asks still open on its list.
# socket, never the keyboard: this has to arrive labelled as another agent, not as JJ typing.
route: socket
---

Deckhand idle check for the session named {name} — this is the Mac's daemon, not JJ. {name} is
the name Claude Code registered for you in ~/.claude/sessions/, which is not always what your
harness calls you, so check that before concluding anything. If you are certain you are not
{name}, this message has been misrouted: say so and do nothing else in reply to it. If you are
unsure, answer the asks below rather than assume a misroute. You have stopped with asks still
open on JJ's list: {listed}. Answer in your own reply in this session, not by messaging another session — the Mac reads
your transcript and nothing else. Name each id and what is true of it: already done
under another name, superseded, waiting on him, decided against, or genuinely still to do. Your
reply is what corrects the list, so an explanation closes an ask as surely as finishing it does —
answer first, and carry on working only where you judge an ask is unfinished and you can finish
it now. Two or three lines is enough. Nothing to do if you have already answered this.
