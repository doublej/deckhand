"""Every web address a session wrote down, and what is true of it now.

A session names addresses constantly — the dev server it started, the NAS it copied to, a page it
read — and they sit in its transcript, and its subagents' transcripts, as dead text. This finds
them (`finding.py`), asks each one whether it loads, wants a password and can be reached from
off this Mac (`checking.py`), and says which ones atlas knows about (`atlas.py`). All of it runs
here: the phone draws the rows `routes.py` hands it and decides nothing.

`routes` is never imported here, for the reason `settings/` gives.
"""
