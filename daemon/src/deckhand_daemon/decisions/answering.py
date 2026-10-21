"""Taking a decision's answer: every check, in the contract's order, then one atomic write.

The order is the contract's and it is not arbitrary. Who signed comes first — no proof, no key,
a bad signature — so a caller without the phone's key learns nothing about the page, not even
whether it exists. Then what was signed: the right session and slip, recently. Only then the page
itself: there, still the version that was signed, not lapsed, not already answered.

**First answer wins, and the file system decides it.** The answer is written to a part file and
hard-linked into place, which fails if an answer is already there — so two taps racing each other
cannot both write, and a second tap is told what the first one said instead of overwriting it.
The answer is the record and is written before anything is typed: a delivery that fails is
retried by the sweep (`announcing.py`), never a lost answer.
"""

from __future__ import annotations

import json
import os
import secrets
import time
from pathlib import Path

from fastapi import HTTPException

from .. import artifacts, sessions
from ..pairing import devices
from . import pages, proofs

#: How far the phone's clock and this Mac's may disagree before a proof is refused as replayed.
WINDOW = 300.0


def refusal(status: int, code: str, error: str, **more: object) -> HTTPException:
    """One shape for every refusal: `{"detail": {"code", "error", ...}}`. The app reads `code`."""
    return HTTPException(status_code=status, detail={"code": code, "error": error, **more})


def located(session: sessions.Session, session_id: str, artifact_id: str
            ) -> tuple[Path, Path] | None:
    """The page and its answer file, by the asker's id from the path rather than the session's.

    After a `/clear` the session found is the successor, whose own folder is not the one the
    question was asked from. The asker's folder first, then the folder's flat scope — the same
    order `artifacts` resolves in, held to the same one-segment rule.
    """
    root = artifacts.project(session)
    spots = [root / session_id, root] if artifacts.ID.fullmatch(session_id) else [root]
    for spot in spots:
        page = artifacts.inside(spot, artifact_id, ".html")
        if page is not None and page.is_file():
            answer = artifacts.inside(spot, artifact_id, ".answer.json")
            return (page, answer) if answer is not None else None
    return None


def taken(proof: object, token: str, session: sessions.Session, session_id: str,
          artifact_id: str) -> tuple[dict, Path, Path, dict]:
    """Check one signed answer and write it down. `(record, page, answer file, page metas)`.

    Raises the refusal the contract names for the first check that fails.
    """
    device, said = proven(proof, token, session=session_id, artifact=artifact_id)
    payload, signature = str(proof.get("payload", "")), str(proof.get("signature", ""))
    found = located(session, session_id, artifact_id)
    if found is None:
        raise HTTPException(status_code=404, detail="no artifact with that id in this project")
    page, answer = found
    current = pages.hashed(page)
    if said.get("hash") != current:
        raise refusal(409, "STALE", "the question changed since it was drawn", hash=current)
    metas = pages.declared(page) or {}
    if time.time() > metas.get("expires", 0.0):
        raise refusal(410, "EXPIRED", "this decision lapsed before it was answered")
    record = {
        "id": artifact_id, "answeredAt": time.time(), "value": said["value"], "verified": True,
        "device": device["name"], "fingerprint": device.get("fingerprint"), "hash": current,
        "delivered": False, "session": session_id,
        "proof": {"payload": payload, "signature": signature},
    }
    if not _written_first(answer, record):
        raise refusal(409, "ANSWERED", "this decision already has an answer",
                      answer=pages.kept(answer))
    return record, page, answer, metas


def proven(proof: object, token: str, **expected: str) -> tuple[dict, dict]:
    """`(device, signed payload)` when `proof` is a filed phone key's, signed for `expected`.

    Who signed, then what was signed, then when — raising UNSIGNED, NO_KEY, BAD_SIGNATURE,
    MISMATCH or OLD_PROOF for the first that fails. A decision expects its session and slip; a
    notify (`push/callbacks.py`) expects the session `notify` and its own id.
    """
    if not isinstance(proof, dict):
        raise refusal(403, "UNSIGNED", "a decision is answered only with the phone's signature")
    device = devices.known(token)
    if device is None or "scope" in device or not device.get("key"):
        raise refusal(403, "NO_KEY", "only a paired phone with a filed key answers a decision")
    said = proofs.verify(device["key"], str(proof.get("payload", "")),
                         str(proof.get("signature", "")))
    if said is None:
        raise refusal(403, "BAD_SIGNATURE", "that signature is not this phone's over that payload")
    if (said.get("v") != proofs.VERSION or "value" not in said
            or any(said.get(field) != wanted for field, wanted in expected.items())):
        raise refusal(400, "MISMATCH", "the signed payload is for another session or slip")
    at = said.get("at")
    if isinstance(at, bool) or not isinstance(at, int | float) or abs(time.time() - at) > WINDOW:
        raise refusal(403, "OLD_PROOF", f"signed more than {int(WINDOW)} s from now")
    return device, said


def _written_first(answer: Path, record: dict) -> bool:
    """Write the answer unless one is already there. False when it was.

    A part file hard-linked into place: the link is atomic and refuses an existing name, which is
    the whole of "first answer wins". The part file goes either way.
    """
    part = answer.with_name(f".{answer.name}.{secrets.token_hex(4)}.part")
    part.write_text(json.dumps(record, indent=2))
    try:
        os.link(part, answer)
    except FileExistsError:
        return False
    finally:
        part.unlink()
    return True


def mark_delivered(answer: Path, record: dict) -> None:
    """Say on the record that the words reached the session, so the sweep stops retrying."""
    part = answer.with_name(f".{answer.name}.{secrets.token_hex(4)}.part")
    part.write_text(json.dumps(record | {"delivered": True}, indent=2))
    part.replace(answer)
