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
import sys
import uuid

from .fleet import here, remote
from .log import log
from .sessions import Session, sessions_dir

TIMEOUT = 5.0
TYPE_TIMEOUT = 15
MSG_VERSION = 1
# Both keys are spelled as CSI-u escape sequences rather than as the bare control bytes they
# stand for, and that spelling is the whole reason a long prompt submits. Claude Code's input
# tokenizer only splits a control byte out as a keypress when the whole read is under 64 bytes;
# in a longer one it is folded into the surrounding text run and arrives as characters. The
# words and the return are two writes, but a session slow to drain its tty reads both as one
# chunk — measured here: a reader stalled for six seconds took a 122-byte read holding the
# words *and* the return — and at that size the return is typed instead of pressed, which is a
# prompt left staged in the box. An escape sequence is tokenised out of a read of any size.
# `\x1b[13u` decodes to `return` and `\x1b[117;5u` to ctrl-U, the same keys with no length to
# be wrong about.
CLEAR_LINE = "\x1b[117;5u"  # ctrl-U: a half-typed line is not part of what was said
RETURN = "\x1b[13u"
# The receiver already wraps a socket message in its own "another Claude session sent this"
# framing, so this only has to say who is actually speaking — and it has to be short, because
# it sits in JJ's pane taking up room he wanted for the message.
PREAMBLE = "JJ, spoken:"


ROUTES = ("auto", "keyboard", "socket")

ESCAPE = "\x1b"
# The three things you can do to a session that are not saying something to it. Each one is
# keystrokes into its pane, because that is what they are when you are sitting at the machine:
# there is no other way to interrupt a run, and a slash command is typed like any other line.
CONTROLS = {
    "cancel": (ESCAPE,),
    "compact": (CLEAR_LINE + "/compact", RETURN),
    "clear": (CLEAR_LINE + "/clear", RETURN),
    # Quits Claude Code. Nothing on the phone can start one again, so this is the one control
    # whose cost is the session itself rather than what is in it.
    "exit": (CLEAR_LINE + "/exit", RETURN),
}


def control(session: Session, action: str) -> str | None:
    """Interrupt, compact or clear. Returns None on success, or why not.

    The peer socket is no help here — it delivers a message, and none of these is a message.
    A session with no pane simply cannot be controlled from the phone, and says so.
    """
    bursts = CONTROLS.get(action)
    if bursts is None:
        return f"no such control {action!r}"
    if not session.pane:
        return f"{session.name} has no iTerm pane — nothing to press keys in"
    for burst in bursts:
        if not _keystrokes(session.pane.iterm_session_id, burst):
            return f"iTerm would not send {action} to {session.name}"
    log.info("sent %s to %s", action, session.name)
    return None


MAX_NAME = 60


def rename(session: Session, name: str) -> str | None:
    """Give the session a new display name. Returns None on success, or why not.

    `/rename` is Claude Code's own command and it takes the name as an argument, so this is the
    same two keystroke bursts as anything else typed into the pane. The registry only picks the
    new name up once the session runs the command, which for a busy one is when its turn ends —
    so a rename can look like nothing happened for a while, and that is the truth of it.
    """
    wanted = clean_name(name)
    if not wanted:
        return "a name cannot be empty"
    if not session.pane:
        return f"{session.name} has no iTerm pane — nothing to type the rename into"
    for burst in (CLEAR_LINE + f"/rename {wanted}", RETURN):
        if not _keystrokes(session.pane.iterm_session_id, burst):
            return f"iTerm would not rename {session.name}"
    log.info("renamed %s to %s", session.name, wanted)
    return None


def clean_name(name: str) -> str:
    """One line of ordinary characters. This is typed into a live prompt, so a newline in it
    would submit half a command and leave the rest sitting in the box."""
    flat = " ".join(name.split())
    return "".join(c for c in flat if c.isprintable())[:MAX_NAME].strip()


def with_images(text: str, paths: list[str]) -> str:
    """The words, and where the pictures are.

    A path is how an image reaches a session: Claude Code's own `Read` shows it a file, so a
    message naming one is a message it can see. Nothing is encoded into the prompt and nothing
    depends on the terminal's paste handling — which is not reachable from a phone anyway.
    """
    if not paths:
        return text
    named = " ".join(paths)
    label = "attached image" if len(paths) == 1 else "attached images"
    return f"{text}\n\n{label}: {named}" if text.strip() else f"{label}: {named}"


def deliver(session: Session, text: str, route: str = "auto") -> tuple[str | None, str | None]:
    """Returns (route taken, error). Never raises: a session that has gone is not an exception.

    The route is the person's choice, because the two are not interchangeable. The keyboard
    carries their authority and needs a pane; the socket always arrives but is stamped as coming
    from another agent. `auto` takes the keyboard when there is a pane and the socket when there
    is not.
    """
    # One line, and nothing in it that is not a character. A control byte left in the words
    # would be read as a keypress of its own once they are typed — an ESC in a prompt cancels
    # the turn it was meant to start — and this is the one place both routes pass through.
    message = "".join(c for c in " ".join(text.split()) if c == " " or c.isprintable())
    if not message:
        return None, "nothing to deliver"
    if route not in ROUTES:
        return None, f"no such route {route!r}"
    # A slash command is only a command where it is typed. Down the socket it is a *message* that
    # happens to start with a slash — the receiving session reads it as words, runs nothing, and
    # nothing anywhere reports a failure, because nothing failed. Refusing is the only way that
    # is ever found out about.
    if message.startswith("/") and (route == "socket" or not session.pane):
        return None, (f"{message.split()[0]} is a slash command and only works typed into a "
                      f"pane; {session.name} would receive it as words")
    if route != "socket" and session.pane:
        if _type_into_pane(session.pane.iterm_session_id, message):
            log.info("typed %d chars into %s's pane", len(message), session.name)
            return "keyboard", None
        if route == "keyboard":
            return None, f"iTerm would not type into {session.name}"
    if route == "keyboard":
        return None, f"{session.name} has no iTerm pane to type into"
    # A session on another machine takes the same last step, one machine over. The guard is here
    # rather than in each caller because every one of them — `say`, a clip, a slip's answer, the
    # idle check, the manager — routes through this function, and a guard per caller would be
    # five places to forget. Above this line nothing changes: the keyboard route has already
    # refused (a remote session has no pane) and so has a slash command, for the same reason.
    if session.machine and session.machine != here():
        delivered, error = remote.deliver_to(session.machine, session.session_id, message)
    else:
        delivered, error = _through_socket(session, message)
    return ("socket" if delivered else None), error


def _type_into_pane(pane_id: str, message: str) -> bool:
    """Type the words and press return, so they arrive as the person's own prompt.

    Only ever aimed at a pane whose tty carries a live `claude` process — that is how the pane
    was found — so the text lands in a prompt, never in a shell.

    Two keystroke bursts. Ctrl-U leads the first, because a half-finished line already sitting
    in the prompt would otherwise be glued to the front of what was said; the return follows in
    its own write, so a refusal between the two is still a failure this can report. Neither key
    relies on that separation to be read as a keypress — both are CSI-u sequences, which
    survive arriving in the same chunk as the words. The constants say why that matters.

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
    """The fallback: always available, but the receiver knows it is not the user speaking.

    **The frames are the same on every machine; only the door differs.** Claude Code listens on
    an `AF_UNIX` socket on macOS and Linux and on a named pipe on Windows, and writes the path
    of whichever it made into the session record — so the payload is built once here and the two
    writers below differ in nothing but how they open it.
    """
    path = session.socket_path
    if not path:
        return False, f"{session.name} has no inbox socket"
    payload = _frames(_peer_token(session.pid), f"{PREAMBLE} {message}")
    sent, error = (
        _write_pipe(path, payload) if sys.platform == "win32" else _write_unix(path, payload)
    )
    if error is not None:
        return False, error.format(name=session.name)
    log.info("delivered %d chars to %s over its peer inbox", len(message), session.name)
    return sent, None


def _write_unix(path: str, payload: bytes) -> tuple[bool, str | None]:
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(TIMEOUT)
            client.connect(path)
            client.sendall(payload)
            client.shutdown(socket.SHUT_WR)
    except FileNotFoundError:
        return False, "{name} is not listening — its inbox socket is gone"
    except ConnectionRefusedError:
        return False, "{name} has exited — its inbox socket is stale"
    except (OSError, TimeoutError) as error:
        return False, f"could not reach {{name}}: {error}"
    return True, None


def _write_pipe(path: str, payload: bytes) -> tuple[bool, str | None]:
    r"""The same frames down a Windows named pipe (`\\.\pipe\LOCAL\cc-msg-…`).

    Opened as a file, because that is what a named pipe is to everything but the process that
    made it: Claude Code's listener there is node's own `net` server, which makes a byte-stream
    pipe, so `write` puts exactly the same newline-delimited JSON on the wire that `sendall`
    does on the other two machines.

    Unbuffered, and closed by the `with`: the receiver reads until the write end goes, which is
    what `shutdown(SHUT_WR)` is doing on the POSIX side.
    """
    try:
        with open(path, "wb", buffering=0) as pipe:
            pipe.write(payload)
    except FileNotFoundError:
        return False, "{name} is not listening — its inbox pipe is gone"
    except OSError as error:
        return False, f"could not reach {{name}}: {error}"
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
