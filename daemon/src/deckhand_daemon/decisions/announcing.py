"""One notification per decision, and the retries that get a verified answer typed in.

Run by the push sweep (`push.sweep`) for every live session, off the listing it already read.

**One alert, keyed by `<sid>:<aid>:<hash>`.** A waiting decision nobody was told about gets one
APNs alert to the phone, with the decision on it so the notification's own buttons can answer it.
Which triples were announced is a file, not a set in memory: a daemon restart then announces the
decisions that were never announced and none that were — the old `was is None` rule treated every
slip sitting there at start-up as history, which is how a decision asked during a restart was
never seen. A rewritten page is a new hash, so it is a new question and is announced again.

**The Live Activity and the Mac stay quiet about it.** `push._slipped` moves the card silently for
a decision, and the Mac's `/alerts` never lists one — P1 answers decisions on the phone alone.

**An answer the asker has not had yet is retried every pass**, until it lands or the decision
lapses: the session was busy at a permission prompt, its pane was gone a moment, or the delivery
failed. Only a verified answer, only into the session id that asked.
"""

from __future__ import annotations

import hashlib
import json
import time

from .. import config
from ..log import log
from ..push import sending
from ..settings import wants
from . import answering, delivery, pages

CATEGORY = {"confirm": "DECISION_CONFIRM", "pick": "DECISION_PICK", "text": "DECISION_TEXT"}
#: APNs refuses a longer `apns-collapse-id`.
MAX_COLLAPSE = 64
#: How many announced triples the file keeps.
#: ponytail: a capped list, oldest dropped; prune by live sessions if it ever matters.
KEEP = 500
#: Triples whose alert failed, so a phone with no device token is one log line, not one a sweep.
_failed: set[str] = set()


def _path():
    return config.data_dir() / "decisions-announced.json"


def announced() -> list[str]:
    """Every `<sid>:<aid>:<hash>` this Mac has sent an alert for, oldest first."""
    try:
        held = json.loads(_path().read_text())
    except (OSError, json.JSONDecodeError):
        return []
    return held if isinstance(held, list) else []


def _remember(triple: str) -> None:
    kept = [*announced(), triple][-KEEP:]
    part = _path().with_suffix(".json.part")
    part.write_text(json.dumps(kept))
    part.replace(_path())


def open_decision(listed: list[dict]) -> bool:
    """Whether a decision on this listing is still waiting for the person."""
    return any(row.get("decision") and not row["answered"] and not row.get("expired")
               for row in listed)


def swept(session, listed: list[dict]) -> None:
    """Announce what is new, retry what was answered and not yet typed. One session, one pass."""
    for row in listed:
        if not row.get("decision"):
            continue
        if row["answered"]:
            _retry(session, row)
        elif not row.get("expired"):
            _announce(session, row)


def collapse_id(session_id: str, artifact_id: str) -> str:
    """`<sid>:<aid>`, or its sha256 hex where that would pass APNs' 64 bytes."""
    key = f"{session_id}:{artifact_id}"
    return key if len(key.encode()) <= MAX_COLLAPSE else hashlib.sha256(key.encode()).hexdigest()


def payload(session, row: dict) -> dict:
    """The alert: the session's name over the question, its category, and the decision itself."""
    sid = session.session_id
    return {
        "aps": {"alert": {"title": session.name or "Deckhand", "body": row["title"]},
                "sound": "default", "category": CATEGORY[row["decision"]], "thread-id": sid},
        "session": sid,
        # What a tap opens: the slip itself, full screen. The app reads `link` first.
        "link": f"deckhand://sessions/{sid}/slips/{row['id']}",
        "decision": {"session": sid, "artifact": row["id"], "hash": row["hash"],
                     "kind": row["decision"], "choices": row["choices"],
                     "question": row["title"]},
    }


def _announce(session, row: dict) -> None:
    triple = f"{session.session_id}:{row['id']}:{row['hash']}"
    if triple in announced() or not wants.resolved(session.cwd).slips:
        return
    error = sending.alert(payload(session, row), collapse_id(session.session_id, row["id"]))
    if error is None:
        _remember(triple)
        _failed.discard(triple)
        log.info("decision %s in %s: the phone was told", row["id"], session.name)
    elif triple not in _failed:
        _failed.add(triple)
        log.info("decision %s in %s: %s", row["id"], session.name, error)


def _retry(session, row: dict) -> None:
    if not row.get("verified") or time.time() > (row.get("expires") or 0):
        return
    found = answering.located(session, session.session_id, row["id"])
    record = pages.kept(found[1]) if found else None
    if record is None or record.get("delivered") or record.get("session") != session.session_id:
        return
    metas = {key: row[key] for key in ("decision", "choices", "action", "expires")}
    delivery.handed(session.session_id, row["id"], row["title"], metas, record, found[1])
