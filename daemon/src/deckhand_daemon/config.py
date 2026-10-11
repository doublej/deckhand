"""Where the daemon keeps its state, and the token every client must present."""

from __future__ import annotations

import os
import secrets
import socket
import sys
from pathlib import Path

PORT = 4180
MAX_UPLOAD_BYTES = 32 * 1024 * 1024
# What may be served back out. Nothing like the upload cap, which is sized for a spoken clip:
# a video a session rendered is routinely bigger than every clip ever recorded into it, and it
# is streamed from disk rather than held in memory at either end.
MAX_FILE_BYTES = 512 * 1024 * 1024
TOKEN_HEADER = "x-deckhand-token"


def data_dir() -> Path:
    """Runtime state root. DECKHAND_DATA_DIR overrides it (tests, temp instances).

    A hand runs this same package on Linux or Windows, where `~/Library/Application Support` is
    not a path anybody would find twice. Everything a hand keeps here is its token, so the
    platform default only has to be somewhere ordinary and writable.
    """
    if override := os.environ.get("DECKHAND_DATA_DIR"):
        root = Path(override)
    elif sys.platform == "darwin":
        root = Path.home() / "Library" / "Application Support" / "Deckhand"
    elif sys.platform == "win32":
        root = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local")) / "Deckhand"
    else:
        root = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / "deckhand"
    root.mkdir(parents=True, exist_ok=True)
    return root


def audio_dir(session_id: str) -> Path:
    d = data_dir() / "audio" / session_id
    d.mkdir(parents=True, exist_ok=True)
    return d


def image_dir(session_id: str) -> Path:
    """Where a picture sent from the phone lands, per session.

    It stays after delivery on purpose: the message names the path and the session reads the
    file, which it may do minutes later or twice.
    """
    d = data_dir() / "images" / session_id
    d.mkdir(parents=True, exist_ok=True)
    return d


def token() -> str:
    """Read the pairing token, creating one on first run. 12 chars: typable on a phone.

    `DECKHAND_TOKEN` overrides it, and that is how a hand gets one: the daemon starts it over
    ssh with its own token in the environment, so there is no second secret to mint, fetch or
    keep in step. One token for the fleet is safe here because the only way to a hand is an
    authenticated ssh session to a port bound on loopback.
    """
    if given := os.environ.get("DECKHAND_TOKEN"):
        return given
    path = data_dir() / "token"
    if path.exists():
        existing = path.read_text().strip()
        if existing:
            return existing
    fresh = secrets.token_urlsafe(9)
    path.write_text(fresh + "\n")
    path.chmod(0o600)
    return fresh


def claude_homes() -> list[Path]:
    """Every Claude Code config dir on this Mac, `~/.claude` first.

    A session started with `CLAUDE_CONFIG_DIR=~/.claude-pimpelmees` writes its record and its
    transcript under that dir and nowhere in `~/.claude`, so a daemon reading only the one was
    blind to it. The others are found as siblings named `<home>-*` holding a `sessions/` folder:
    that is the convention here, and the `sessions/` test keeps out `~/.claude-monitor` and the
    like, which are not config dirs at all. DECKHAND_CLAUDE_HOME moves the whole family, which
    is what keeps a test's tmp root from picking up this Mac's real sessions.
    """
    home = Path(os.environ.get("DECKHAND_CLAUDE_HOME", Path.home() / ".claude"))
    others = sorted(p for p in home.parent.glob(f"{home.name}-*") if (p / "sessions").is_dir())
    return [home, *others]


def base_url() -> str:
    """The URL to type into the app. .local name over an IP: it survives DHCP."""
    return f"http://{socket.gethostname()}:{PORT}"


def lan_address() -> str:
    """This Mac's address on the network, for rewriting a localhost link into a reachable one.

    A session writes `http://localhost:5173` because that is true where it is running. On a phone
    it is true of the phone, which is running nothing. Asking a UDP socket which interface would
    carry a packet out is the one way to get this that needs no name to resolve — the socket is
    never connected and nothing is sent.
    """
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("192.0.2.1", 9))  # TEST-NET-1: routable to nowhere, so nothing leaves
        return probe.getsockname()[0]
    except OSError:
        return ""
    finally:
        probe.close()
