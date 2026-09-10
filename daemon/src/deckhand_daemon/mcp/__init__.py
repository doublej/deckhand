"""Deckhand's tools for the agent working inside a session, over stdio.

A separate process from the daemon, started by Claude Code itself and living as long as the
session does. It ships in this package because everything it needs — the token path, the port,
httpx — is already here; it is not a second package and not a route on the daemon, which binds
`0.0.0.0` for the phone and so cannot host one safely.
"""
