"""The tray: every session that needs the person, and what happened to the ones that did.

Two halves, on purpose. **What is open** is never stored: it is read off the disk each time it is
asked for — the slips nobody has answered, on every machine, and the line a session used to call
for you — so it cannot disagree with the slips tab or with a Lock Screen card. **What happened**
is a numbered list on disk (`feed.py`), written by the Lock Screen's own sweep as it notices each
thing, and read by cursor like the manager's conversation.

`shapes.py` is what makes a slip answerable without its page: the four kinds `slip.py` writes say
in their markup exactly what they ask. `routes.py` is `GET /tray` on the Mac and `GET /tray/open`
on a hand. Nothing is imported here, so `push/` can write the feed without importing the routes
that read `push/`.
"""
