"""The Codex threads on this Mac, over the app server's own control socket.

Codex owns its threads, their permissions and their model. Deckhand asks the app server which
interactive threads are loaded, starts an ordinary durable thread when the phone asks for one, and
puts the person's words into a thread through Codex's own turn lane. Nothing else.

**The socket speaks WebSocket, not newline JSON.** `<CODEX_HOME>/app-server-control/
app-server-control.sock` answers an HTTP upgrade — and closes after 0 bytes when the handshake
carries the library's default `User-Agent`, `Origin` or `permessage-deflate` offer, which is what
the three `None`s in `_linked` are for. `codex app-server proxy` spoken to in newline JSON never
answers at all. Measured against the running app server 0.153.4 on 2026-09-13.

**One link, read all the time.** The link is held rather than opened per call, on the understanding
that a thread this daemon starts stays loaded only while a connection is subscribed to it — not
measured, because nothing that writes was run against the real server. A reader thread takes every
frame off it the moment it lands, so a subscribed thread's stream never backs up into the socket
between two of our requests. Notifications and the server's own requests (approvals among them)
are dropped unanswered: answering one would be this daemon deciding for whichever client the
person is actually using.

**Codex's only way in carries the person's own authority.** `turn/start` and `turn/steer` arrive as
the user typing; there is no peer inbox and no wrapper saying another agent sent this. So `deliver`
refuses the socket route rather than substitute one authority for the other, and everything that
speaks *as an agent* — the manager, the idle check, the MCP tool — refuses a Codex session before
it gets this far.

**The listing is `thread/read` per loaded id, never `thread/list`.** Measured on 2026-09-13:
`thread/list {limit: 1000}` took 2.6-2.8 s and 245 KB for a page the server capped at 100 threads,
and 5 of the 7 loaded ids were not on it. `thread/loaded/list` costs 12 ms and one read ~46 ms;
seven reads sent pipelined took the same 329 ms as seven sent in turn, so they go in turn. A child
thread stays a child, so its id is remembered and it is never read again.
"""

from __future__ import annotations

import json
import os
import queue
import socket
import threading
import time
from pathlib import Path
from typing import TYPE_CHECKING

from websockets.exceptions import WebSocketException
from websockets.sync.client import ClientConnection, unix_connect

from ..log import log

if TYPE_CHECKING:
    from .live import Session

#: What the listing waits, per call, before the app server counts as not answering. The listing is
#: built under the lock every route waits on, so this is what a hung server costs `/sessions`.
TIMEOUT = 2.0
#: What a call the person made waits: starting a thread, reading its turns, putting words in.
WAIT = 15.0
#: After a listing got no answer, how long before the listing asks again. `panes.PANE_RETRY_AFTER`
#: in another key: a server that has gone costs its timeout once, never once per poll.
RETRY_AFTER = 30.0
#: One round's full items measured 375 KB and two measured 2.3 MB, past the library's 1 MB default.
MAX_FRAME = 64 * 1024 * 1024
HELLO = {"clientInfo": {"name": "deckhand", "version": "1"},
         "capabilities": {"experimentalApi": True}}


class CodexError(RuntimeError):
    """Codex answered, and the answer was no."""


class Unreachable(CodexError):
    """The app server is not there, or did not answer in time."""


def socket_path() -> Path:
    home = os.environ.get("DECKHAND_CODEX_HOME") or Path.home() / ".codex"
    return Path(home) / "app-server-control" / "app-server-control.sock"


class _Link:
    """One introduced connection, and the thread that reads everything off it."""

    def __init__(self, connection: ClientConnection) -> None:
        self._connection = connection
        self._waiting: dict[int, queue.SimpleQueue[dict | None]] = {}
        self._sending = threading.Lock()
        self._sent = 0
        self.closed = False
        threading.Thread(target=self._read, name="codex-link", daemon=True).start()

    def call(self, method: str, params: dict, timeout: float) -> dict:
        answer: queue.SimpleQueue[dict | None] = queue.SimpleQueue()
        with self._sending:
            self._sent += 1
            mine = self._sent
            self._waiting[mine] = answer
            self._connection.send(json.dumps(
                {"jsonrpc": "2.0", "id": mine, "method": method, "params": params}))
        try:
            message = answer.get(timeout=timeout)
        except queue.Empty:
            raise TimeoutError(f"no answer to {method} in {timeout:g} s") from None
        finally:
            self._waiting.pop(mine, None)
        if message is None:
            raise ConnectionError("the app server closed the connection")
        if error := message.get("error"):
            raise CodexError(str(error.get("message") if isinstance(error, dict) else error))
        result = message.get("result")
        return result if isinstance(result, dict) else {}

    def notify(self, method: str) -> None:
        """A notification carries no id, and nothing answers it."""
        with self._sending:
            self._connection.send(json.dumps({"jsonrpc": "2.0", "method": method, "params": {}}))

    def close(self) -> None:
        self.closed = True
        self._connection.close()

    def _read(self) -> None:
        try:
            for frame in self._connection:
                message = json.loads(frame)
                # An answer has an id and no method. A request from the server has both and a
                # notification has no id; nothing here is waiting for either.
                answers = isinstance(message, dict) and "method" not in message
                if answers and (waiter := self._waiting.get(message.get("id"))) is not None:
                    waiter.put(message)
        except (WebSocketException, OSError, ValueError) as error:
            log.info("codex link closed: %s", error)
        finally:
            self.closed = True
            for waiter in list(self._waiting.values()):
                waiter.put(None)


_link: _Link | None = None
_linking = threading.Lock()
#: When the listing last asked, and whether it was answered. `/health` reads the second half.
_asked: tuple[float, bool] = (0.0, False)
#: Loaded ids already read once and found to have a parent. A child thread never stops being one.
# ponytail: one id per subagent thread for the life of the daemon; a set of short strings.
_children: set[str] = set()


def request(method: str, params: dict | None = None, timeout: float = WAIT) -> dict:
    """Call the app server once. The seam every caller goes through and every test replaces."""
    try:
        return _linked().call(method, params or {}, timeout)
    except (OSError, WebSocketException) as error:
        _drop()
        raise Unreachable(f"the Codex app server is not answering: {error}") from error


def _linked() -> _Link:
    """The open link, made and introduced when there is none."""
    global _link
    # Windows' Python has no `AF_UNIX`, and `unix_connect` says so with an AttributeError — not an
    # OSError, so nothing caught it and Fractal's hand answered every listing 500 for weeks.
    if not hasattr(socket, "AF_UNIX"):
        raise Unreachable("this Python has no unix sockets to reach the app server on")
    with _linking:
        if _link is None or _link.closed:
            fresh = _Link(unix_connect(
                str(socket_path()), uri="ws://localhost/", compression=None,
                user_agent_header=None, origin=None, open_timeout=TIMEOUT, max_size=MAX_FRAME,
                legacy=True))
            try:
                fresh.call("initialize", HELLO, TIMEOUT)
                fresh.notify("initialized")
            except BaseException:
                fresh.close()  # half an introduction must not keep its socket and its reader
                raise
            _link = fresh
        return _link


def _drop() -> None:
    global _link
    with _linking:
        if _link is not None:
            _link.close()
        _link = None


def answered() -> bool:
    """Whether the app server answered the last listing that asked it. False before any has."""
    return _asked[1]


def records() -> list[dict]:
    """The loaded, top-level Codex threads that can take input, as session records.

    Never raises: Codex being absent, down or hung is a listing with no Codex rows in it, never a
    listing without the Claude ones. After a failure it does not ask again for `RETRY_AFTER`.
    """
    global _asked
    at, ok = _asked
    if at and not ok and time.monotonic() - at < RETRY_AFTER:
        return []
    try:
        threads = _loaded()
    except CodexError as error:
        if ok or not at:
            log.warning("codex threads unavailable: %s", error)
        _asked = (time.monotonic(), False)
        return []
    _asked = (time.monotonic(), True)
    return [record(thread) for thread in threads
            if not thread.get("parentThreadId") and _state(thread) in ("active", "idle")]


def _loaded() -> list[dict]:
    """Every loaded thread not already known to be a child, read one at a time."""
    found = []
    for thread_id in request("thread/loaded/list", {}, TIMEOUT).get("data") or []:
        if thread_id in _children:
            continue
        thread = _read(str(thread_id))
        if thread.get("parentThreadId"):
            _children.add(str(thread_id))
        found.append(thread)
    return found


def _read(thread_id: str) -> dict:
    """One thread, or {} when it was unloaded between being listed and being read."""
    try:
        thread = request("thread/read", {"threadId": thread_id}, TIMEOUT).get("thread")
    except Unreachable:
        raise
    except CodexError:
        return {}
    return thread if isinstance(thread, dict) else {}


def record(thread: dict) -> dict:
    """One thread in the shape `live.Session` is built from."""
    cwd = str(thread.get("cwd") or "")
    return {
        "session_id": str(thread.get("id") or ""),
        "pid": 0,
        # A name is a key for stars and filter chains. A folder's bare name is the Claude session's
        # there, and a thread the phone just started has no name of its own yet.
        "name": str(thread.get("name") or f"{Path(cwd).name}-codex-{str(thread.get('id'))[-4:]}"),
        "cwd": cwd,
        "status": "busy" if _state(thread) == "active" else "idle",
        "updated_at": float(thread.get("updatedAt") or 0),  # whole seconds, unlike Claude's ms
        "tty": "",
        "pane": None,
        "provider": "codex",
    }


def _state(thread: dict) -> str:
    status = thread.get("status")
    return str(status.get("type") or "") if isinstance(status, dict) else ""


def start(cwd: str) -> dict:
    """Start a durable thread in `cwd` and answer with its record.

    No model, approval policy or sandbox: those are Codex's own configuration, and that is the
    answer JJ chose rather than a default this daemon picked.
    """
    thread = request("thread/start", {"cwd": cwd, "ephemeral": False}).get("thread")
    if not isinstance(thread, dict) or not thread.get("id"):
        raise CodexError("Codex answered without the thread it started")
    log.info("started codex thread %s in %s", thread["id"], cwd)
    return record(thread)


def deliver(session: Session, message: str, route: str) -> tuple[str | None, str | None]:
    """The person's words into a thread: a new turn when idle, into the running one when busy.

    Returns (route taken, error) exactly as `deliver.deliver` does, and never raises.
    """
    if route == "socket":
        return None, (f"{session.name} is a Codex thread: it has no peer inbox, and its only way "
                      f"in carries your own authority — speak into it on auto or keyboard")
    if message.startswith("/"):
        return None, (f"{message.split()[0]} is a slash command, and Codex takes none over its "
                      f"app server; {session.name} would receive it as words")
    words = [{"type": "text", "text": message}]
    try:
        running = active_turn(session.session_id) if session.status == "busy" else None
        if running:
            request("turn/steer", {"threadId": session.session_id, "input": words,
                                   "expectedTurnId": running})
        else:
            request("turn/start", {"threadId": session.session_id, "input": words})
    except CodexError as error:
        return None, f"Codex would not take the words for {session.name}: {error}"
    taken = "codex-steered" if running else "codex-direct"
    log.info("%s took %d chars as %s", session.name, len(message), taken)
    return taken, None


def active_turn(thread_id: str) -> str | None:
    """The id of the turn running in this thread now, or None. The list is newest first."""
    turns = request("thread/turns/list",
                    {"threadId": thread_id, "limit": 1, "itemsView": "notLoaded"}).get("data")
    newest = turns[0] if turns and isinstance(turns[0], dict) else {}
    return str(newest["id"]) if newest.get("status") == "inProgress" else None


def interrupt(session: Session) -> str | None:
    """Stop the running turn. None once Codex has been asked, otherwise why not."""
    try:
        running = active_turn(session.session_id)
        if running is None:
            return f"{session.name} has no turn running to stop"
        request("turn/interrupt", {"threadId": session.session_id, "turnId": running})
    except CodexError as error:
        return f"Codex would not stop {session.name}: {error}"
    log.info("interrupted %s", session.name)
    return None
