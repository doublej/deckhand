"""The manager's tools over MCP's streamable HTTP, at `/mcp` on the daemon itself.

For a client that is not on this Mac — reached from outside as
`https://deckhand-mcp.jurrejan.com/mcp`, the NAS Caddy passing `/mcp` and nothing else. The same
server `deckhand-manager-mcp` speaks over stdio, with the daemon's own handlers rather than
forwarded ones, because this already is the daemon.

**A bearer token, and a scope of its own.** MCP clients send `Authorization: Bearer`, so that is
the one header read here. This Mac's token or a paired device's works, but the one meant for this
is `python -m deckhand_daemon.pairing manager-token NAME`: it reaches `/mcp` and no other route,
so a token pasted into some tool's settings cannot type into a pane, read a file or open a pairing
window — only do what the manager does.

**Stateless, answering JSON.** Every call is one POST with one answer and nothing held between
them, so a proxy in front and a daemon restart behind are both invisible to the client.
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from mcp.server.streamable_http_manager import StreamableHTTPSessionManager
from starlette.responses import JSONResponse

from .. import pairing
from . import manager

_sessions: StreamableHTTPSessionManager | None = None


@asynccontextmanager
async def serving():
    """The session manager, for the daemon's lifespan. Made here rather than at import: one may
    only be run once, and a test app has a lifespan of its own."""
    global _sessions
    _sessions = StreamableHTTPSessionManager(app=manager.build(forwarded=False), stateless=True,
                                             json_response=True)
    async with _sessions.run():
        yield
    _sessions = None


class _Gate:
    """`/mcp` as a raw ASGI app — the transport writes its own answer — behind the token."""

    async def __call__(self, scope, receive, send) -> None:
        given = dict(scope["headers"]).get(b"authorization", b"").decode()
        if not pairing.allows_manager(given.removeprefix("Bearer ").strip()):
            await JSONResponse({"detail": "bad token"}, status_code=401)(scope, receive, send)
            return
        await _sessions.handle_request(scope, receive, send)


endpoint = _Gate()
