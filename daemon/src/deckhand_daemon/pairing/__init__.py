"""Who may talk to this daemon: this Mac's own token, and a token per paired device.

Read `docs/install-and-pairing.md` before changing anything here; the shape is a security
decision and that page is where it was made.

- **This Mac's token is unchanged.** `config.token()`, the file `just token` prints, is still
  accepted everywhere, and is the only token that opens a pairing window or revokes a device. The
  CLI, the MCP server, utt's page, the Mac app and every hand read it off disk, so nothing on
  this Mac had to change, and every phone and headset paired before this exists keeps working.
- **A paired device holds a token of its own** (`devices.py`), minted by `POST /pair` in
  exchange for the six-digit code the person at the Mac opened (`window.py`). Revoking it is
  `DELETE /devices/{id}`, and touches no other device.
- **A scoped token can do one thing.** `python -m deckhand_daemon.pairing transcribe-token NAME`
  mints a device whose row carries `scope: transcribe`: a web page may hold it to call `POST /transcribe` and nothing else, so a
  browser's localStorage never holds a token that can speak into a session. `allows` refuses it
  everywhere; `allows_transcribe` is the one place it counts. `manager-token NAME` is the same
  for `/mcp`, the manager's tools over HTTP (`mcp/remote.py`), and `allows_manager` its check.
- **`allows` is the one question**, asked by `app.require_token` and by the two middlewares that
  answer before a route's own dependency runs (`fleet/routing.py`, `sessions/codex_routes.py`).
  A check of its own anywhere else is a door this module does not know about.
"""

from __future__ import annotations

import secrets

from .. import config
from . import devices

#: `POST /transcribe`, and nothing else on this daemon.
TRANSCRIBE = "transcribe"
#: `/mcp`, the manager's tools, and nothing else on this daemon.
MANAGER = "manager"


def allows(given: str) -> bool:
    """Whether a request carrying this token may be answered.

    `compare_digest` rather than `!=`: this Mac's token is also every hand's token, so it is
    compared far more often and by more processes than it was, and a comparison that returns
    early leaks where it stopped. The cost is nothing and the property is free.
    """
    if not given:
        return False
    if secrets.compare_digest(given, config.token()):
        return True
    device = devices.known(given)
    return device is not None and "scope" not in device


def allows_transcribe(given: str) -> bool:
    """`allows`, or a token minted for `/transcribe` alone."""
    return _allows_scope(given, TRANSCRIBE)


def allows_manager(given: str) -> bool:
    """`allows`, or a token minted for `/mcp` alone."""
    return _allows_scope(given, MANAGER)


def _allows_scope(given: str, scope: str) -> bool:
    if allows(given):
        return True
    device = devices.known(given) if given else None
    return device is not None and device.get("scope") == scope
