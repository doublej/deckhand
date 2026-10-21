"""What the decision tests share: the ids, a signed proof, a decision page, the answer post.

The key is a software P-256 key made here, the same curve and encoding the Secure Enclave key
uses: the daemon sees a 65-byte point and DER signatures either way.
"""

import base64
import json
import time

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi.testclient import TestClient

from deckhand_daemon import config
from deckhand_daemon.app import app
from deckhand_daemon.decisions import pages

SID = "aaaa1111-2222-3333-4444-555566667777"
AID = "ship-it"


def b64(raw: bytes) -> str:
    return base64.b64encode(raw).decode()


def public_key(private: ec.EllipticCurvePrivateKey) -> str:
    """The x963 point, base64 — what the phone sends `PUT /devices/key`."""
    return b64(private.public_key().public_bytes(
        serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint))


def signed(private, **fields) -> dict:
    """A proof over the payload as the phone builds it: sorted keys, no spaces."""
    payload = json.dumps(fields, sort_keys=True, separators=(",", ":")).encode()
    return {"payload": b64(payload),
            "signature": b64(private.sign(payload, ec.ECDSA(hashes.SHA256())))}


def page_html(kind="confirm", choices=("Ship", "Hold"), action="push the tag, nothing else",
              expires=None) -> str:
    when = int(expires if expires is not None else time.time() + 3600)
    return ("<!doctype html><html><head><meta charset=\"utf-8\">\n"
            f'<meta name="deckhand-decision" content="{kind}">\n'
            f'<meta name="deckhand-choices" content="{json.dumps(list(choices)).replace(chr(34), "&quot;")}">\n'
            f'<meta name="deckhand-action" content="{action}">\n'
            f'<meta name="deckhand-expires" content="{when}">\n'
            "<title>Ship it?</title></head><body><h1>Ship it?</h1></body></html>")


def proof_for(key, page, value=None, at=None, **over) -> dict:
    """A proof for this page as it is now, with any field overridden."""
    fields = {"v": 1, "session": SID, "artifact": AID, "hash": pages.hashed(page),
              "value": {"answer": True} if value is None else value,
              "at": int(time.time()) if at is None else at} | over
    return signed(key, **fields)


def answering(token, proof=None, body=None):
    """POST the answer the way the phone does."""
    return TestClient(app).post(f"/sessions/{SID}/artifacts/{AID}/answer",
                                json=body if body is not None else {"proof": proof},
                                headers={config.TOKEN_HEADER: token})
