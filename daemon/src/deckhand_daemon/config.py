"""Where the daemon keeps its state, and the token every client must present."""

from __future__ import annotations

import os
import secrets
import socket
from pathlib import Path

PORT = 4180
MAX_UPLOAD_BYTES = 32 * 1024 * 1024
TOKEN_HEADER = "x-deckhand-token"


def data_dir() -> Path:
    """Runtime state root. DECKHAND_DATA_DIR overrides it (tests, temp instances)."""
    override = os.environ.get("DECKHAND_DATA_DIR")
    root = Path(override) if override else Path.home() / "Library" / "Application Support" / "Deckhand"
    root.mkdir(parents=True, exist_ok=True)
    return root


def audio_dir(session_id: str) -> Path:
    d = data_dir() / "audio" / session_id
    d.mkdir(parents=True, exist_ok=True)
    return d


def token() -> str:
    """Read the pairing token, creating one on first run. 12 chars: typable on a phone."""
    path = data_dir() / "token"
    if path.exists():
        existing = path.read_text().strip()
        if existing:
            return existing
    fresh = secrets.token_urlsafe(9)
    path.write_text(fresh + "\n")
    path.chmod(0o600)
    return fresh


def base_url() -> str:
    """The URL to type into the app. .local name over an IP: it survives DHCP."""
    return f"http://{socket.gethostname()}:{PORT}"
