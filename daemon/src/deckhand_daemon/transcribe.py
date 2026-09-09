"""Speech to text through utt, the on-device transcriber running on this Mac.

utt's API only accepts connections from this Mac, which is where the daemon runs. Its bearer
token lives in 1Password as `deckhand/UTT_SECRET`. onenv is the source of truth, but it cannot
run under launchd — 1Password has no way to ask for a fingerprint there — so `just sync-secrets`
materialises the value into the data dir and the daemon reads that. Order: environment, then
the materialised file, then onenv for a daemon started by hand.

utt re-mints that token whenever its API is switched off and on again, which leaves the copy in
1Password stale and every clip answered with a 401. Rather than fail until someone runs
`just sync-secrets`, a rejected token is retried once against utt's own settings file, which is
where the live value lives.
"""

from __future__ import annotations

import json
import os
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

from .log import log

UTT_URL = os.environ.get("UTT_URL", "http://127.0.0.1:8756")
ONENV_KEY = ("deckhand", "UTT_SECRET")
UTT_SETTINGS = Path.home() / "Library/Application Support/dev.jurrejan.utt/settings.json"
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


def _from_utt_settings() -> str | None:
    """The token utt is actually holding right now. Read only after 1Password's copy is refused."""
    try:
        return (json.loads(UTT_SETTINGS.read_text()).get("api") or {}).get("token") or None
    except (OSError, json.JSONDecodeError, AttributeError):
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
    global _token
    secret = token()
    if not secret:
        return None, "no utt token on this Mac — run `just sync-secrets`"
    text, error, rejected = _post(clip, secret)
    if not rejected:
        return text, error
    live = _from_utt_settings()
    if not live or live == secret:
        return text, error
    log.warning("utt refused the token from 1Password; using the one utt is holding")
    _token = live
    text, error, _ = _post(clip, live)
    return text, error


def _post(clip: Path, secret: str) -> tuple[str | None, str | None, bool]:
    """One attempt. The third value says the token was refused, which is worth a second try."""
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
        return (text, None, False) if text else (None, "nothing recognisable in that clip", False)
    except urllib.error.HTTPError as error:
        return None, _message(error), error.code == 401
    except urllib.error.URLError as error:
        # Nothing on the port means the app is not open. Say that, not the errno.
        if isinstance(error.reason, ConnectionRefusedError):
            return None, "utt is not running on the Mac — open utt and try again", False
        return None, f"utt did not answer: {error.reason}", False
    except (TimeoutError, json.JSONDecodeError) as error:
        return None, f"utt did not answer: {error}", False


def _message(error: urllib.error.HTTPError) -> str:
    """utt answers a failure with one sentence; pass it through rather than inventing one."""
    try:
        return f"{error.code}: {json.loads(error.read()).get('error', error.reason)}"
    except (json.JSONDecodeError, OSError):
        return f"{error.code}: {error.reason}"
