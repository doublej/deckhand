"""The phone's signature: what it covers, how it is checked, and how a kept answer is re-checked.

The phone holds a P-256 key in its Secure Enclave and hands this Mac the public half once, as the
65-byte uncompressed point (`x963`), base64. An answer to a decision is a **proof**: the exact
bytes of a small JSON payload, base64, and an ECDSA-SHA256 signature over those bytes in DER,
base64. The bytes are verified as they arrived and only then parsed, so key order and whitespace
are the phone's business and nothing here re-serialises anything before checking it.

    {"v":1,"session":"<sid>","artifact":"<aid>","hash":"<page sha256>","value":<value>,"at":<unix s>}

`daemon/tests/decisions/vector.json` is one such triple the Swift side checks its own encoding
against; a change to the encoding here has to move that file and the app together.
"""

from __future__ import annotations

import base64
import binascii
import hashlib
import json

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec

from ..pairing import devices

VERSION = 1
#: The uncompressed point: 0x04, then 32 bytes of x and 32 of y.
KEY_BYTES = 65


def key_from(encoded: str) -> bytes | None:
    """The key's raw bytes when `encoded` is a base64 P-256 point, else None."""
    try:
        raw = base64.b64decode(encoded, validate=True)
        ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), raw)
    except (binascii.Error, ValueError):
        return None
    return raw if len(raw) == KEY_BYTES else None


def fingerprint(raw: bytes) -> str:
    """The first 8 bytes of sha256(key), in hex — what a person can compare by eye."""
    return hashlib.sha256(raw).digest()[:8].hex()


def verify(key: str, payload: str, signature: str) -> dict | None:
    """The signed payload, parsed, when `signature` is `key`'s over exactly `payload`'s bytes.

    None for anything that is not that: a key, payload or signature that does not decode, a
    signature that does not verify, or signed bytes that are not a JSON object.
    """
    try:
        raw_key = base64.b64decode(key, validate=True)
        signed = base64.b64decode(payload, validate=True)
        public = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), raw_key)
        public.verify(base64.b64decode(signature, validate=True), signed,
                      ec.ECDSA(hashes.SHA256()))
        said = json.loads(signed)
    except (binascii.Error, ValueError, InvalidSignature):
        return None
    return said if isinstance(said, dict) else None


def holds(written: dict, current_hash: str, artifact: str) -> bool:
    """Whether a kept answer is still the person's: verified again, never taken off the file.

    The file is in the session's folder and an agent can write one by hand, `verified: true`
    included. What it cannot write is a signature, so this finds the device the file names by its
    fingerprint, verifies the kept proof against that device's key, and holds the payload to the
    page as it is now and to the value the file says was answered.
    """
    proof = written.get("proof")
    device = devices.keyed(str(written.get("fingerprint", "")))
    if not isinstance(proof, dict) or device is None:
        return False
    said = verify(device["key"], str(proof.get("payload", "")), str(proof.get("signature", "")))
    return (said is not None and said.get("hash") == current_hash == written.get("hash")
            and said.get("artifact") == artifact and said.get("value") == written.get("value"))
