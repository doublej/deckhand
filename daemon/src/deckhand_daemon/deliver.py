"""Puts a line of text into a running Claude Code session. Two ways, and the difference matters.

**The keyboard.** `tmux send-keys -l` types the words into the session's tmux pane and presses
return. They arrive as a prompt from the person at the machine, because that is exactly what
they are: the daemon is holding JJ's keyboard for him. Nothing frames them as second-hand, and
a session can act on them with the authority it gives anything its user types. This needs a
pane, which means the session has to be running inside tmux.

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
import sys
import time
import uuid

from . import config, presence
from .fleet import here, remote
from .log import log
from .reading.transcripts import transcript_path
from .sessions import Session, codex, opencode_input, panes, teammates

TIMEOUT = 5.0
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
# Ctrl-U clears back to the start of the *wrapped* line only, and one more takes the line break:
# a prompt Escape pulled back out of the queue kept all but its last line glued to the next one.
CLEAR_BOX = CLEAR_LINE * 100  # fifty wrapped lines, in one write under the tty's read
RETURN = "\x1b[13u"
# A pane's tty hands Claude Code at most 1022 bytes per read, so one `send-keys` longer
# than that arrives as two reads a fraction of a millisecond apart — and Claude Code keeps only
# one of them often enough to matter. Measured against a live session on 2026-09-13, a
# 1212-character message: sent as one write with the ctrl-U on its front, mangled 13 times in 52;
# every failure arrived with its first 1014 characters simply gone and only the tail submitted,
# which is a prompt that *looks* delivered and says something else. Ctrl-U on its own write took
# it to 1 in 14, a bare message to 1 in 24, and the words chopped below the buffer to 0 in 46 —
# including at 4000 characters. So each write stays under the buffer, and ctrl-U and the return
# keep the writes of their own they already had. The CSI-u spelling is why the *keys* survive a
# shared read; nothing makes the *words* survive one.
BURST = 1000
# How long the session's own transcript is watched for the words before they count as staged.
# Measured over 130 real sends: median 0.5 s, slowest 2.2 s.
SUBMITTED = 3.0
POLL = 0.05
REFUSED = "tmux would not type into {name}"
STAGED = "{name} took the words but not the return — they are sitting unsent in its box"
# The receiver already wraps a socket message in its own "another Claude session sent this"
# framing, so this only has to say who is actually speaking — and it has to be short, because
# it sits in JJ's pane taking up room he wanted for the message.
PREAMBLE = "JJ, spoken:"


ROUTES = ("auto", "keyboard", "socket")
#: The providers whose words go in over their own server's API: provider -> its `deliver`.
SERVED = {"codex": codex.deliver, "opencode": opencode_input.deliver}

ESCAPE = "\x1b"
# The three things you can do to a session that are not saying something to it. Each one is
# keystrokes into its pane, because that is what they are when you are sitting at the machine:
# there is no other way to interrupt a run, and a slash command is typed like any other line.
CONTROLS = {
    "cancel": (ESCAPE,),
    "compact": (CLEAR_BOX, "/compact", RETURN),
    "clear": (CLEAR_BOX, "/clear", RETURN),
    # Quits Claude Code. Nothing on the phone can start one again, so this is the one control
    # whose cost is the session itself rather than what is in it.
    "exit": (CLEAR_BOX, "/exit", RETURN),
}


def control(session: Session, action: str) -> str | None:
    """Interrupt, compact or clear. Returns None on success, or why not.

    The peer socket is no help here — it delivers a message, and none of these is a message.
    A session with no pane simply cannot be controlled from the phone, and says so.
    """
    bursts = CONTROLS.get(action)
    if bursts is None:
        return f"no such control {action!r}"
    if session.provider == "opencode":  # its own API stops and compacts, with no pane
        return opencode_input.control(session, action)
    if not session.pane:
        return f"{session.name} is not in a tmux pane — nothing to press keys in"
    if aimed := teammates.bring_back(session, CLEAR_BOX):  # Escape there would interrupt the teammate
        return aimed
    for burst in bursts:
        if not panes.press(session.pane.iterm_session_id, burst):
            return f"tmux would not send {action} to {session.name}"
    log.info("sent %s to %s", action, session.name)
    return None


MAX_NAME = 60


def rename(session: Session, name: str) -> str | None:
    """Give the session a new display name. Returns None on success, or why not.

    `/rename` is Claude Code's own command and it takes the name as an argument, so this is the
    same keystroke bursts as anything else typed into the pane. The registry only picks the
    new name up once the session runs the command, which for a busy one is when its turn ends —
    so a rename can look like nothing happened for a while, and that is the truth of it.
    """
    wanted = clean_name(name)
    if not wanted:
        return "a name cannot be empty"
    if session.provider == "opencode":  # its title, which its API sets at once, busy or not
        return opencode_input.rename(session, wanted)
    if not session.pane:
        return f"{session.name} is not in a tmux pane — nothing to type the rename into"
    if aimed := teammates.bring_back(session, CLEAR_BOX):
        return aimed
    for burst in (CLEAR_BOX, f"/rename {wanted}", RETURN):
        if not panes.press(session.pane.iterm_session_id, burst):
            return f"tmux would not rename {session.name}"
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
    from another agent. `auto` takes the keyboard when there is a pane and nobody at the laptop,
    and the socket otherwise.
    """
    # One line, and nothing in it that is not a character. A control byte left in the words
    # would be read as a keypress of its own once they are typed — an ESC in a prompt cancels
    # the turn it was meant to start — and this is the one place both routes pass through.
    message = "".join(c for c in " ".join(text.split()) if c == " " or c.isprintable())
    if not message:
        return None, "nothing to deliver"
    if route not in ROUTES:
        return None, f"no such route {route!r}"
    # Codex and OpenCode take words over their own server's API rather than a pane or a socket,
    # so which routes may reach them, and slashes, are theirs to decide. Codex's one lane carries
    # the person's authority; OpenCode keeps both, and `socket` is its agent lane.
    if served := SERVED.get(session.provider):
        return served(session, message, route)
    # A slash command is only a command where it is typed. Down the socket it is a *message* that
    # happens to start with a slash — the receiving session reads it as words, runs nothing, and
    # nothing anywhere reports a failure, because nothing failed. Refusing is the only way that
    # is ever found out about.
    if message.startswith("/") and (route == "socket" or not session.pane):
        return None, (f"{message.split()[0]} is a slash command and only works typed into a "
                      f"pane; {session.name} would receive it as words")
    # `auto` keeps off a keyboard the person is sitting at: two things typing into one pane
    # interleave and neither notices. A slash command still types, because the socket would
    # turn it into words, and the person asked for the one thing only the pane can do.
    if route == "auto" and not message.startswith("/") and presence.where() == "laptop":
        route = "socket"
    if route != "socket" and session.pane and (aimed := teammates.bring_back(session, CLEAR_BOX)):
        if route == "keyboard" or message.startswith("/"):
            return None, aimed
        route = "socket"  # still a teammate's box: `auto` takes the lead's own inbox instead
    if route != "socket" and session.pane:
        failed = _type_into_pane(session.pane.iterm_session_id, message, session.session_id)
        if failed is None:
            log.info("typed %d chars into %s's pane", len(message), session.name)
            return "keyboard", None
        log.warning("%s", failed.format(name=session.name))
        # Only a pane that would not take the keys at all leaves the socket a job. Words already
        # sitting in a session's box are not words to say again down another route: it would end
        # up holding both, and the person said one thing once.
        if route == "keyboard" or failed == STAGED:
            return None, failed.format(name=session.name)
    if route == "keyboard":
        return None, f"{session.name} is not in a tmux pane to type into"
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


def _type_into_pane(pane_id: str, message: str, session_id: str) -> str | None:
    """Type the words and press return, so they arrive as the person's own prompt.

    None once the session has them; otherwise why it has not, as a template naming it.

    Only ever aimed at a pane whose tty carries a live `claude` process — that is how the pane
    was found — so the text lands in a prompt, never in a shell.

    Ctrl-U leads, in a write of its own, because a half-finished line already sitting in the
    prompt would otherwise be glued to the front of what was said; the return follows in its
    own write, so a refusal between the two is still a failure this can report. Neither key
    needs that separation to be read as a keypress — both are CSI-u sequences, which survive
    arriving in the same chunk as the words. The *words* need it, and need the chopping too:
    `BURST` says what a read costs one that gets it wrong.

    Then the question the log used to answer with a guess: did it go in. A staged message and a
    sent one look the same on the screen, so this asks the session's own transcript
    instead, which is the log of what arrived rather than of what was written at it.
    """
    watch = _watch(session_id)
    for burst in (CLEAR_BOX, *_pieces(message), RETURN):
        if not panes.press(pane_id, burst):
            return REFUSED
    if watch is None or _arrived(session_id, watch, message):
        return None
    # The words are in the box and the return was not taken. Press it again — on a box the
    # first one already emptied this does nothing at all, so it cannot send anything twice.
    # A shorter window this time: the words are already typed, so there is nothing left to wait
    # for but the submit, and the phone is holding a clip open the whole while.
    panes.press(pane_id, RETURN)
    return None if _arrived(session_id, watch, message, SUBMITTED / 3) else STAGED


def _pieces(message: str) -> list[str]:
    """The words as writes small enough that the pane's tty hands each of them to one read.

    Cut by bytes and not by characters, because the buffer is bytes and a sentence of accented
    words is half again as long once it is UTF-8 — and never through the middle of a character,
    which would put two broken halves on the wire.
    """
    raw, pieces = message.encode(), []
    while raw:
        cut = BURST
        while cut < len(raw) and raw[cut] & 0xC0 == 0x80:  # a continuation byte: back off
            cut -= 1
        pieces.append(raw[:cut].decode())
        raw = raw[cut:]
    return pieces


def _watch(session_id: str) -> int | None:
    """How long this session's transcript is before anything is typed, so only what is appended
    afterwards has to be read back. None when there is no transcript to watch — which is not the
    same as a failure, and is the one case where the keys being accepted is all that is known."""
    path = transcript_path(session_id)
    return path.stat().st_size if path else None


def _arrived(session_id: str, watch: int, message: str, budget: float = SUBMITTED) -> bool:
    """Whether the session's own transcript says it took the words, within `budget`.

    The transcript is the only honest answer: an idle session writes the prompt as a turn and a
    busy one writes a `queue-operation` for its inbox, and both land inside a second. The whole
    message is looked for rather than its opening, because the failure this catches is a prompt
    arriving with its front missing — an opening that matched would be the half that was lost.
    """
    # Piece by piece, because that is how a long message is typed — and a pane that is busy takes
    # each piece as a paste of its own, wrapping it and writing it as its own entry. The whole
    # message is then in the transcript but never in one place, and looking for it whole reported
    # a delivered prompt as unsent: the card came back on the phone and the person sent it again.
    wanted = [json.dumps(piece, ensure_ascii=False)[1:-1] for piece in _pieces(message)]
    end = time.monotonic() + budget
    while True:
        path = transcript_path(session_id)
        if path is not None:
            with path.open("rb") as file:
                file.seek(watch)
                seen = file.read().decode(errors="replace")
            if all(piece in seen for piece in wanted):
                return True
        if time.monotonic() >= end:
            return False
        time.sleep(POLL)


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
    socket path exactly the way Claude Code canonicalises it, for a value already on disk. The
    key sits beside the record, so in whichever config dir that session was started under.
    """
    for key in (
        k for home in config.claude_homes() for k in (home / "sessions").glob(f"{pid}.*.key")
    ):
        try:
            return json.loads(key.read_text()).get("peerToken")
        except (OSError, json.JSONDecodeError):
            return None
    return None
