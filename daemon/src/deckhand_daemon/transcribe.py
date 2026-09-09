"""Speech to text through utt, the on-device transcriber running on this Mac.

utt's API only accepts connections from this Mac, which is where the daemon runs. Its bearer
token lives in 1Password as `deckhand/UTT_SECRET`. onenv is the source of truth, but it cannot
run under launchd — 1Password has no way to ask for a fingerprint there — so `just sync-secrets`
materialises the value into the data dir and the daemon reads that. Order: environment, then
the materialised file, then onenv for a daemon started by hand.
"""

from __future__ import annotations

import json
import os
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

UTT_URL = os.environ.get("UTT_URL", "http://127.0.0.1:8756")
ONENV_KEY = ("deckhand", "UTT_SECRET")
_token: str | None = None
# The first request after utt launches compiles and loads the model; that is the slow one.
TIMEOUT = 180
CONTENT_TYPES = {
    ".m4a": "audio/mp4",
    ".mp4": "audio/mp4",
    ".wav": "audio/wav",
    ".caf": "audio/caf",
    ".mp3": "audio/mpeg",
    ".aac": "audio/mp4",
    ".aiff": "audio/aiff",
    ".flac": "audio/flac",
    ".ogg": "audio/wav",
    ".webm": "audio/wav",
}


def token() -> str | None:
    """utt's bearer token. Cached: both a file read and a 1Password read are worth doing once."""
    global _token
    if _token:
        return _token
    _token = os.environ.get("UTT_SECRET", "").strip() or _from_file() or _from_onenv()
    return _token


def _from_file() -> str | None:
    """The value `just sync-secrets` copied out of 1Password. The only path launchd can use."""
    from . import config

    path = config.data_dir() / "utt-token"
    try:
        return path.read_text().strip() or None
    except OSError:
        return None


def _from_onenv() -> str | None:
    """Straight from 1Password. Works when a person started the daemon, hangs under launchd."""
    namespace, key = ONENV_KEY
    try:
        result = subprocess.run(
            ["onenv", "get", namespace, key],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout.strip() or None


def transcribe(clip: Path) -> tuple[str | None, str | None]:
    """Returns (text, error). Never raises: a clip that cannot be transcribed is still stored."""
    secret = token()
    if not secret:
        return None, "no utt token on this Mac — run `just sync-secrets`"
    request = urllib.request.Request(
        f"{UTT_URL}/transcribe",
        data=clip.read_bytes(),
        method="POST",
        headers={
            "Authorization": f"Bearer {secret}",
            "Content-Type": CONTENT_TYPES.get(clip.suffix.lower(), "audio/wav"),
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            text = (json.loads(response.read()).get("text") or "").strip()
        # utt answers 200 with an empty string for a clip it could make no words out of.
        # Saying so beats showing a blank line and calling it a transcript.
        return (text, None) if text else (None, "nothing recognisable in that clip")
    except urllib.error.HTTPError as error:
        return None, _message(error)
    except urllib.error.URLError as error:
        # Nothing on the port means the app is not open. Say that, not the errno.
        if isinstance(error.reason, ConnectionRefusedError):
            return None, "utt is not running on the Mac — open utt and try again"
        return None, f"utt did not answer: {error.reason}"
    except (TimeoutError, json.JSONDecodeError) as error:
        return None, f"utt did not answer: {error}"


def _message(error: urllib.error.HTTPError) -> str:
    """utt answers a failure with one sentence; pass it through rather than inventing one."""
    try:
        return f"{error.code}: {json.loads(error.read()).get('error', error.reason)}"
    except (json.JSONDecodeError, OSError):
        return f"{error.code}: {error.reason}"
