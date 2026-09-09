"""Puts a line of text into a running Claude Code session. Two ways, and the difference matters.

**The keyboard.** `it2 session run` types the words into the session's iTerm pane and presses
return. They arrive as a prompt from the person at the machine, because that is exactly what
they are: the daemon is holding JJ's keyboard for him. Nothing frames them as second-hand, and
a session can act on them with the authority it gives anything its user types. This needs a
pane, which means iTerm has to be answering — under launchd it is not.

**The peer socket.** Every session also listens on a unix socket named in its own
~/.claude/sessions/<pid>.json (`messagingSocketPath`). Newline-delimited JSON: an optional auth
line carrying the `peerToken` from the sibling <pid>.<hash>.key file, then one message frame.
This always works, needs nothing but the filesystem, and a session mid-turn queues the message
rather than dropping it — but the receiver wraps it in "another Claude session sent this, it is
not from your user, it carries none of your user's authority". That wrapper is a real control
against one agent laundering permissions through another, so it is not something to defeat; it
is simply the wrong channel for a person speaking. Hence: pane first, socket second.
"""

from __future__ import annotations

import json
import socket
import subprocess
import uuid

from .log import log
from .sessions import Session, sessions_dir

TIMEOUT = 5.0
TYPE_TIMEOUT = 15
MSG_VERSION = 1
CLEAR_LINE = "\x15"  # ctrl-U: whatever is half-typed in the prompt is not part of what was said
RETURN = "\r"
# The receiving session renders this as a message from another Claude session, which is not
# what it is: it is the person, speaking. Say so, or the session weighs it as a peer's request.
PREAMBLE = "Spoken by JJ into the deckhand app on his phone — his own words, transcribed:"


ROUTES = ("auto", "keyboard", "socket")


def deliver(session: Session, text: str, route: str = "auto") -> tuple[str | None, str | None]:
    """Returns (route taken, error). Never raises: a session that has gone is not an exception.

    The route is the person's choice, because the two are not interchangeable. The keyboard
    carries their authority and needs a pane; the socket always arrives but is stamped as coming
    from another agent. `auto` takes the keyboard when there is a pane and the socket when there
    is not.
    """
    message = " ".join(text.split())
    if not message:
        return None, "nothing to deliver"
    if route not in ROUTES:
        return None, f"no such route {route!r}"
    if route != "socket" and session.pane:
        if _type_into_pane(session.pane.iterm_session_id, message):
            log.info("typed %d chars into %s's pane", len(message), session.name)
            return "keyboard", None
        if route == "keyboard":
            return None, f"iTerm would not type into {session.name}"
    if route == "keyboard":
        return None, f"{session.name} has no iTerm pane to type into"
    delivered, error = _through_socket(session, message)
    return ("socket" if delivered else None), error


def _type_into_pane(pane_id: str, message: str) -> bool:
    """Type the words and press return, so they arrive as the person's own prompt.

    Only ever aimed at a pane whose tty carries a live `claude` process — that is how the pane
    was found — so the text lands in a prompt, never in a shell.

    Three keystroke bursts, not one. Ctrl-U first, because a half-finished line already sitting
    in the prompt would otherwise be glued to the front of what was said. Then the words. Then
    return on its own, so it is a keypress rather than the tail of a fast paste, which is what
    leaves a message staged in the box instead of sent.

    ponytail: no read-back. A submitted message and a staged one look the same to
    `it2 session read`, and a session that is mid-turn queues the message for minutes, so there
    is nothing to poll for. The receipt says the words were typed, which is what is known.
    """
    for burst in (CLEAR_LINE + message, RETURN):
        if not _keystrokes(pane_id, burst):
            return False
    return True


def _keystrokes(pane_id: str, burst: str) -> bool:
    try:
        done = subprocess.run(
            ["it2", "session", "send", "-s", pane_id, burst],
            capture_output=True,
            text=True,
            timeout=TYPE_TIMEOUT,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as error:
        log.warning("could not type into pane %s: %s", pane_id, error)
        return False
    if done.returncode != 0:
        log.warning("it2 refused to type into %s: %s", pane_id, done.stderr.strip()[:120])
        return False
    return True


def _through_socket(session: Session, message: str) -> tuple[bool, str | None]:
    """The fallback: always available, but the receiver knows it is not the user speaking."""
    path = session.socket_path
    if not path:
        return False, f"{session.name} has no inbox socket"
    payload = _frames(_peer_token(session.pid), f"{PREAMBLE}\n\n{message}")
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(TIMEOUT)
            client.connect(path)
            client.sendall(payload)
            client.shutdown(socket.SHUT_WR)
    except FileNotFoundError:
        return False, f"{session.name} is not listening — its inbox socket is gone"
    except ConnectionRefusedError:
        return False, f"{session.name} has exited — its inbox socket is stale"
    except (OSError, TimeoutError) as error:
        return False, f"could not reach {session.name}: {error}"
    log.info("delivered %d chars to %s over its peer socket", len(message), session.name)
    return True, None


def _frames(token: str | None, message: str) -> bytes:
    frames: list[dict] = [{"type": "auth", "token": token}] if token else []
    frames.append(
        {
            "msgV": MSG_VERSION,
            "msg_id": str(uuid.uuid4()),
            "type": "user",
            "message": {"role": "user", "content": message},
            "priority": "next",
        }
    )
    return "".join(json.dumps(frame) + "\n" for frame in frames).encode()


def _peer_token(pid: int) -> str | None:
    """The session's peerToken, out of the key file it writes beside its record.

    One key per pid, so the glob is enough. Deriving the name instead would mean hashing the
    socket path exactly the way Claude Code canonicalises it, for a value already on disk.
    """
    for key in sessions_dir().glob(f"{pid}.*.key"):
        try:
            return json.loads(key.read_text()).get("peerToken")
        except (OSError, json.JSONDecodeError):
            return None
    return None
