"""One log file, readable in Console.app.

Console shows everything under ~/Library/Logs in its sidebar, so that is where the daemon
writes. Lines are `time  level  message`, one event per line, no tracebacks in the happy path.
"""

from __future__ import annotations

import logging
import logging.handlers
import os
import sys
import time
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

# Tests point this elsewhere: a test run must not write into the log a person is watching.
LOG_DIR = Path(os.environ.get("DECKHAND_LOG_DIR", Path.home() / "Library" / "Logs" / "Deckhand"))
LOG_FILE = LOG_DIR / "deckhand.log"
FORMAT = "%(asctime)s  %(levelname)-5s  %(message)s"
#: What the log may take up, and how far back it goes. Nothing on macOS rotates `~/Library/Logs`
#: — `newsyslog` does not look there — so without this the file only ever grows: 2.0 MB in four
#: days here, about half a megabyte a day, for as long as the Mac is on. Three files of two
#: megabytes is roughly a fortnight, which is longer than any question anybody asks of it.
MAX_BYTES = 2 * 1024 * 1024
KEPT = 2


def setup() -> logging.Logger:
    """Log to the file Console.app can watch, and to the terminal when there is one.

    **Only when there is one.** The stream handler is for `just daemon`, where a person is
    reading; under launchd it wrote every line a second time into `launchd.err.log`, which is
    how that file reached 3.0 MB against the log's own 2.0 MB. Everything it carried is in
    `deckhand.log` already. What is *not* duplicated there — uvicorn's own startup lines, and
    the 2044 `address already in use` failures this agent crash-looped through on 2026-09-11 —
    still reaches `launchd.err.log`, because uvicorn writes those itself.

    On a hand it is the same test and the same answer: over ssh, stderr is a pipe nobody is
    reading, and that pipe is `link.py`'s 64 KB fuse. ssh's own banners still reach the daemon,
    which is what `link.useful_error` was written to read.
    """
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    handlers: list[logging.Handler] = [
        logging.handlers.RotatingFileHandler(LOG_FILE, maxBytes=MAX_BYTES, backupCount=KEPT)
    ]
    if sys.stderr is not None and sys.stderr.isatty():
        handlers.append(logging.StreamHandler())
    formatter = logging.Formatter(FORMAT, datefmt="%Y-%m-%d %H:%M:%S")
    for handler in handlers:
        handler.setFormatter(formatter)
    logger = logging.getLogger("deckhand")
    logger.setLevel(logging.INFO)
    logger.handlers = handlers
    logger.propagate = False
    return logger


log = setup()


@contextmanager
def took(stages: dict[str, float], name: str) -> Iterator[None]:
    """Wall clock for one stage of a clip's journey, in milliseconds, into `stages`.

    Wall clock rather than CPU: every interesting stage here is spent waiting for something else
    — an `it2` subprocess, a disk, utt. Insertion order is the order the stages ran, which is why
    the response and the JSONL both hand the dict straight out rather than sorting it.

    Here rather than in a `timing.py` of its own: `daemon/src/deckhand_daemon/` sits on
    `.quality.json`'s 16-file cap, and this is the module that already means "what the daemon
    says about itself". Do not tidy it into a new file — the gate will fail.
    """
    start = time.perf_counter()
    try:
        yield
    finally:
        stages[name] = round((time.perf_counter() - start) * 1000, 1)
