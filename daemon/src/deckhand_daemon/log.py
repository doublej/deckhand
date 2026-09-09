"""One log file, readable in Console.app.

Console shows everything under ~/Library/Logs in its sidebar, so that is where the daemon
writes. Lines are `time  level  message`, one event per line, no tracebacks in the happy path.
"""

from __future__ import annotations

import logging
import os
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
