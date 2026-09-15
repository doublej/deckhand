"""Web pages pinned to projects, and what the person said about a spot on one.

A **binding** says a page belongs to a project folder: a pattern — an origin plus an optional path
prefix — and the folder. A **feedback entry** is one thing said about one element of such a page,
kept under that folder. Both are whole documents in the data dir beside `settings.json`.

`patterns.py` is the pure half, what a pattern is and which bindings a URL matches, and the place
to start. `stored.py` is the two files. `routes.py` is the wire.

The same import shape as `settings/` and `projects/`: `routes` is never imported here. It pulls in
FastAPI and the rest of the daemon, and `app.py` is the only thing that decides when that happens.
"""
