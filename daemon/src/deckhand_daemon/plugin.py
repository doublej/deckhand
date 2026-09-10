"""Deckhand's page inside utt, and the folder utt transcribes clips in.

utt renders a page for any program that drops a manifest in its plugins folder, and writes the
person's choices back beside it. Nothing is registered and nothing is called: both programs
start and restart in any order, and a file is what survives that.

Two things come back the other way. `<id>.values.json` holds every setting whenever one
changes, so the Mac half of Deckhand finally has somewhere a person can configure it — until
now every setting lived on the phone or nowhere. `<id>.action.json` holds the last button
pressed, which is why the menu bar app's four items can live here instead.

The manifest is written at every start-up rather than once: it is what survives the folder
being deleted, utt being reinstalled, or settings being reset.
"""

from __future__ import annotations

import asyncio
import json
import os
import subprocess
from pathlib import Path
from typing import Any

from . import __version__, config, deliver
from .log import LOG_FILE, log

ID = "deckhand"
DAEMON_LABEL = "com.jurrejan.deckhand"
POLL = 1.0
SUPPORT = Path.home() / "Library" / "Application Support" / "dev.jurrejan.utt"
# utt 1.2 renamed this folder from `plugins` to `extensions`, and the one that exists is
# the one the *installed* utt makes at launch — not the one its source says. Naming either
# outright breaks the file lane against the other build, and silently: a jobs folder that
# is not there makes `transcribe` give up, so hold-to-talk stops working with nothing in
# the log but a missing directory. So ask the disk, newest name first.
NAMES = ("extensions", "plugins")
# Routes are Deckhand's word; the page gets the person's. Same three choices either way.
ROUTE_OPTIONS = {"whichever works": "auto", "typed into the terminal": "keyboard",
                 "sent as a message": "socket"}
DEFAULTS = {"route": "whichever works", "deliver": True, "attribution": "JJ, spoken:"}


def plugins_dir() -> Path:
    """utt makes this at launch. DECKHAND_PLUGIN_DIR points the tests somewhere harmless.

    Whichever of `NAMES` utt actually made, preferring the newer. Falling back to the first name
    when neither exists keeps the failure the one it has always been — a folder that is not there
    — rather than a second kind nobody has seen.
    """
    if named := os.environ.get("DECKHAND_PLUGIN_DIR"):
        return Path(named)
    return next((SUPPORT / name for name in NAMES if (SUPPORT / name).is_dir()),
                SUPPORT / NAMES[0])


def jobs_dir() -> Path:
    return plugins_dir() / f"{ID}.jobs"


def turned_off() -> bool:
    """Whether utt has been told to stop servicing Deckhand.

    utt records this as an empty `<id>.disabled` file rather than a key in the manifest, because
    the manifest is rewritten by the extension at every start-up and a marker survives that. It
    is the whole state — there is nothing else to read.
    """
    return (plugins_dir() / f"{ID}.disabled").is_file()


def route() -> str:
    """The route to use when the phone did not name one."""
    return ROUTE_OPTIONS.get(str(_values.get("route")), "auto")


def delivers() -> bool:
    """False transcribes and shows the words on the phone without putting them anywhere."""
    return bool(_values.get("deliver", True))


def manifest() -> dict[str, Any]:
    """Written every start-up. Every sentence here is read by a person, so none of it names
    a key, a file or a process — utt's own rows read that way and a guest matches its host."""
    return {
        "id": ID,
        "name": "Deckhand",
        "blurb": "Talk to the Claude sessions running on this Mac from your phone.",
        "systemImage": "sailboat",
        "needsApi": False,
        "wantsTranscripts": False,
        "sendsAudio": True,
        # What utt may not do to a clip Deckhand sends it.
        #
        # A prompt on its way into a coding session is not dictation into a text field: the
        # capitals, the punctuation and the exact words are the payload. `formatting` is the
        # stage that lowercases and strips punctuation, and its two switches
        # (`lowercaseTranscripts`, `removePunctuation`) live in the person's own utt settings —
        # so with this unset, one toggle meant for dictation elsewhere silently mangles every
        # prompt this app delivers. Declaring it makes the phone lane deterministic whatever
        # those are set to, and it applies only to Deckhand's own clips.
        #
        # `cleanup` and `replacements` are deliberately kept. Cleanup removes filler words,
        # false starts and stuttered repeats and resolves a mid-sentence self-correction to
        # what was meant — "at five, actually six" becomes "six" — which is exactly the shape a
        # spoken prompt takes, and it is deletion-only with a budget and a whole-transcript
        # fallback. An unknown stage name is dropped rather than refused, so this is safe to
        # send to an older utt.
        "skipsTextStages": ["formatting"],
        "tint": "#3EAFB4",
        "showsInMenuBar": True,
        "daemon": {"label": DAEMON_LABEL},
        # Every action is reachable from the menu bar or none is, so each one here has to be
        # safe to press by accident. There was a "Stop listening" button; it ran `launchctl
        # bootout`, which unloads the job — and utt's Restart is `kickstart`, which cannot
        # revive a job that is not loaded (verified: "Could not find service"). One mis-click
        # would have taken Deckhand down until someone opened a terminal. Stopping it for
        # good is `just uninstall-agent`, which is where a one-way door belongs.
        "actions": [
            {"key": "copyToken", "label": "Copy pairing code",
             "detail": "Puts the code your phone asks for on the clipboard."},
            {"key": "openLog", "label": "Open the log",
             "detail": "Every clip, what it was heard as, and where it went."},
        ],
        "settings": [
            {"key": "route", "kind": "choice", "label": "How your words arrive",
             "options": list(ROUTE_OPTIONS), "value": DEFAULTS["route"],
             "detail": "Typed into the terminal they arrive as you speaking, which needs the "
                       "session to be visible in a window. Sent as a message they always "
                       "arrive, but marked as coming from somewhere other than you."},
            {"key": "deliver", "kind": "bool", "label": "Put the words into the session",
             "value": DEFAULTS["deliver"],
             "detail": "Off, what you say is still written down and shown on your phone, but "
                       "nothing reaches the session."},
            {"key": "attribution", "kind": "string", "label": "Sign your messages with",
             "value": DEFAULTS["attribution"],
             "detail": "Put in front of anything sent as a message, so the session knows the "
                       "words are yours and not another program's."},
        ],
    }


def install() -> None:
    """Manifest first, then a status file, so the page is never blank on its first open."""
    try:
        plugins_dir().mkdir(parents=True, exist_ok=True)
        _write(plugins_dir() / f"{ID}.json", manifest())
    except OSError as error:
        log.warning("could not install the utt plugin page: %s", error)
        return
    _read_values()
    status(daemon=f"listening on {config.base_url()}", version=__version__)


async def watch() -> None:
    """Poll for a changed setting or a pressed button. Once a second is what the guide asks for
    and what a person notices; utt's writes are atomic, so a poll cannot read half a file."""
    while True:
        await asyncio.sleep(POLL)
        try:
            await asyncio.to_thread(_poll)
        except OSError as error:  # a plugin page must never take the daemon down with it
            log.warning("utt plugin poll failed: %s", error)


def status(**fields: object) -> None:
    """A flat object of our own words, shown read-only at the top of the page. Merged rather
    than replaced, so a caller can update one line without knowing the others."""
    _status.update({key: str(value) for key, value in fields.items()})
    try:
        _write(plugins_dir() / f"{ID}.status.json", _status)
    except OSError as error:
        log.warning("could not write the plugin status: %s", error)


_values: dict[str, Any] = dict(DEFAULTS)
_status: dict[str, str] = {}
_revision = -1
_sequence: int | None = None


def _poll() -> None:
    _read_values()
    pressed = _read(plugins_dir() / f"{ID}.action.json")
    global _sequence
    if not (pressed and isinstance(pressed.get("sequence"), int)):
        return
    # First sight of the file is not a press: the button may have been used before we started.
    # Acting on `key` alone would also miss the same button pressed twice.
    if _sequence is not None and pressed["sequence"] > _sequence:
        _act(str(pressed.get("key")))
    _sequence = pressed["sequence"]


def _read_values() -> None:
    """utt never merges, so neither do we: the file holds every setting or it is not there."""
    global _revision
    written = _read(plugins_dir() / f"{ID}.values.json")
    if not written or written.get("revision") == _revision:
        return
    _revision = written.get("revision", -1)
    _values.update(written.get("values") or {})
    deliver.PREAMBLE = str(_values.get("attribution") or DEFAULTS["attribution"])
    log.info("utt page: route %s, deliver %s", _values.get("route"), _values.get("deliver"))


def _act(key: str) -> None:
    """utt writes the key and nothing else — what it means is ours to decide, which is the
    whole reason a manifest cannot name a command to run."""
    log.info("utt page: %s pressed", key)
    if key == "copyToken":
        subprocess.run(["/usr/bin/pbcopy"], input=config.token(), text=True, check=False)
        status(lastAction="pairing code copied")
    elif key == "openLog":
        subprocess.run(["/usr/bin/open", "-a", "Console", str(LOG_FILE)], check=False)


def _write(path: Path, payload: dict) -> None:
    """Temp file then rename, the same way utt writes to us: a reader never sees half a file."""
    temporary = path.with_suffix(path.suffix + ".part")
    temporary.write_text(json.dumps(payload, indent=2))
    temporary.replace(path)


def _read(path: Path) -> dict | None:
    try:
        loaded = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    return loaded if isinstance(loaded, dict) else None
