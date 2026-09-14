"""Deckhand daemon: the Mac side of the iOS remote for live Claude Code sessions."""

__version__ = "0.1.0"


def main() -> None:
    """The process from the outside: `deckhand-daemon`, and `--hand` for the other machines.

    Here rather than in `app.py`, whose job is the endpoints and nothing else — and which sits
    on the 400-line gate, so the next thing it grew had to come out of it. Every import is
    inside the function, because the `--hand` branch must be taken before this one constructs
    the full app, with its utt page, its APNs watcher and its manager.
    """
    import sys

    if "--hand" in sys.argv[1:]:
        from .fleet import hand

        hand.main()
        return

    import uvicorn

    from . import app as service
    from . import config
    from .log import log

    log.info("deckhand %s  token: %s", config.base_url(), config.token())
    uvicorn.run(service.app, host="0.0.0.0", port=config.PORT, log_level="info")
