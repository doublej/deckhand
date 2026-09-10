"""One log file, readable in Console.app.

Console shows everything under ~/Library/Logs in its sidebar, so that is where the daemon
writes. Lines are `time  level  message`, one event per line, no tracebacks in the happy path.
"""

from __future__ import annotations

import logging
import os
import time
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

# Tests point this elsewhere: a test run must not write into the log a person is watching.
LOG_DIR = Path(os.environ.get("DECKHAND_LOG_DIR", Path.home() / "Library" / "Logs" / "Deckhand"))
LOG_FILE = LOG_DIR / "deckhand.log"
FORMAT = "%(asctime)s  %(levelname)-5s  %(message)s"


def setup() -> logging.Logger:
    """Log to the file Console.app can watch, and to stdout for `just daemon`."""
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    handlers: list[logging.Handler] = [logging.FileHandler(LOG_FILE), logging.StreamHandler()]
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
