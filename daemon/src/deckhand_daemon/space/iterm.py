"""iTerm's own Python API, held open under the name `deckhand` — once that name has been approved.

`it2` opens a connection per call and answers plain text. The styled screen and a session's own
profile need the API itself, so the daemon keeps one connection, on a thread and event loop of
its own: the library authenticates with a blocking `osascript`, and that must never run on the
loop serving the phone.

**iTerm asks once, by name, whether a new client may connect**, with a dialog on the Mac's
screen, and every API call waits until somebody answers it. A daemon that connected by itself
would stall on a question nobody is in front of. So it never does: nothing here is imported, let
alone connected, until `iterm-approved` is in the data dir. `just iterm-styles` writes it, after
connecting as `deckhand` from a terminal at the Mac, where JJ sees the dialog and answers it.

Any failure drops the connection and keeps off the API for a minute, the pattern of
`sessions/panes.py`; `/screen` reads plain text through `it2` meanwhile.
"""

from __future__ import annotations

import asyncio
import json
import os
import threading
import time
from collections.abc import Awaitable, Callable
from typing import Any

from .. import config
from ..log import log

NAME = "deckhand"
MARKER = "iterm-approved"
RETRY_AFTER = 60.0
#: Generous for one read (~10 ms) and short enough that a phone poll does not notice a stall.
TIMEOUT = 3.0

_loop: asyncio.AbstractEventLoop | None = None
_started = threading.Lock()
_connecting = asyncio.Lock()
_connection: Any = None
_failed_at = float("-inf")


def approved() -> bool:
    return (config.data_dir() / MARKER).exists()


def ready() -> bool:
    """Approved, and not inside the minute after the API last failed."""
    return approved() and time.monotonic() - _failed_at >= RETRY_AFTER


def call[T](work: Callable[[Any], Awaitable[T]]) -> T | None:
    """`await work(connection)` on the iTerm thread, from a worker thread.

    None when the name is not approved, inside the minute after a failure, or failing now — the
    caller reads plain text instead, whatever the reason was.
    """
    global _failed_at
    if not ready():
        return None
    future = asyncio.run_coroutine_threadsafe(_within(work), _thread_loop())
    try:
        return future.result(TIMEOUT)
    except Exception as error:  # noqa: BLE001 -- every way the API fails ends in plain text
        future.cancel()
        _failed_at = time.monotonic()
        log.warning("iTerm API failed, plain text for %.0f s: %r", RETRY_AFTER, error)
        return None


def screen(pane_id: str) -> list | None:
    """The visible screen, one `LineContents` per row with its styles — the rows `it2 session
    read` prints, so `lines` is the same either way."""

    async def read(connection: Any) -> list:
        from iterm2 import api_pb2, rpc

        sent = await rpc.async_get_screen_contents(connection, pane_id, None, True)
        answer = sent.get_buffer_response
        if answer.status != api_pb2.GetBufferResponse.Status.Value("OK"):
            raise LookupError(api_pb2.GetBufferResponse.Status.Name(answer.status))
        return list(answer.contents)

    return call(read)


def profile(pane_id: str, keys: list[str]) -> dict | None:
    """The pane's profile as it stands, session-local changes included: `keys` only, each value
    the same shape as in iTerm's preferences plist, so one parser reads both."""

    async def read(connection: Any) -> dict:
        from iterm2 import api_pb2, rpc

        answer = (
            await rpc.async_get_profile(connection, pane_id, keys)
        ).get_profile_property_response
        if answer.status != api_pb2.GetProfilePropertyResponse.Status.Value("OK"):
            raise LookupError(api_pb2.GetProfilePropertyResponse.Status.Name(answer.status))
        return {found.key: json.loads(found.json_value) for found in answer.properties}

    return call(read)


def approve() -> None:
    """`just iterm-styles`: connect once as `deckhand`, at the Mac, so iTerm asks and JJ answers.
    Writes the marker only once the connection is through; the daemon reads it on every call, so
    it needs no restart."""
    asyncio.run(_connect())
    (config.data_dir() / MARKER).write_text(f"{NAME}\n")
    print(f"iTerm let '{NAME}' in: /sessions/{{id}}/screen carries styles from now on")


def _thread_loop() -> asyncio.AbstractEventLoop:
    global _loop
    with _started:
        if _loop is None:
            _loop = asyncio.new_event_loop()
            threading.Thread(target=_loop.run_forever, name="iterm", daemon=True).start()
    return _loop


async def _within(work: Callable[[Any], Awaitable[Any]]) -> Any:
    """Runs on the iTerm loop, the only place `_connection` is touched. A failure of any kind,
    a timeout's cancellation included, closes the connection so the next try starts clean."""
    global _connection
    try:
        async with _connecting:
            if _connection is None:
                _connection = await _connect()
        return await work(_connection)
    except BaseException:
        dropped, _connection = _connection, None
        if dropped is not None:
            await dropped.websocket.close()
        raise


async def _connect() -> Any:
    import iterm2  # here and not at the top: without the marker the daemon never loads it

    # The name iTerm puts in its dialog and its script console. The library takes it from
    # `__main__`, which here is `deckhand-daemon`, a test runner or this file; one name is approved.
    iterm2.auth.get_script_name = iterm2.connection.get_script_name = lambda: NAME
    try:
        return await iterm2.Connection.async_create()
    finally:
        # The cookie travels in the environment and is good for one connection. Left there,
        # every `it2` this daemon starts would inherit a spent one, be refused, and ask again.
        os.environ.pop("ITERM2_COOKIE", None)
        os.environ.pop("ITERM2_KEY", None)


if __name__ == "__main__":
    approve()
