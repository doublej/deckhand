"""Puts a line of text into a running Claude Code session, the way a peer session does.

Every session listens on a unix socket named in its own ~/.claude/sessions/<pid>.json
(`messagingSocketPath`). The wire format is newline-delimited JSON: an optional auth line
carrying the `peerToken` from the sibling <pid>.<hash>.key file, then one message frame.
macOS does not require the auth line, but sending it is what makes the daemon a vouched peer
rather than an anonymous writer on the socket, so it goes out whenever the key is readable.

The receiving session renders the text as a message from another Claude session and answers it
in its next turn. A session that is mid-turn queues it rather than dropping it; `priority:
"next"` puts it at the head of that queue. Nothing comes back on the socket — arrival is the
only acknowledgement there is.
"""

from __future__ import annotations

import json
import socket
import uuid

from .log import log
from .sessions import Session, sessions_dir

TIMEOUT = 5.0
MSG_VERSION = 1
# The receiving session renders this as a message from another Claude session, which is not
# what it is: it is the person, speaking. Say so, or the session weighs it as a peer's request.
PREAMBLE = "Spoken by JJ into the deckhand app on his phone — his own words, transcribed:"


def deliver(session: Session, text: str) -> tuple[bool, str | None]:
    """Returns (delivered, error). Never raises: a session that has gone is not an exception."""
    message = text.strip()
    if not message:
        return False, "nothing to deliver"
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
    log.info("delivered %d chars to %s", len(message), session.name)
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
