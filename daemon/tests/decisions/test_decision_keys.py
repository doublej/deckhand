"""The phone's key: what the signature check accepts, and who may file a key at all."""

import base64
import json
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric import ec
from decision_kit import b64, public_key, signed
from fastapi.testclient import TestClient

from deckhand_daemon import config
from deckhand_daemon.app import app
from deckhand_daemon.decisions import proofs
from deckhand_daemon.pairing import TRANSCRIBE, devices

VECTOR = Path(__file__).with_name("vector.json")


def put_key(token, key):
    return TestClient(app).put("/devices/key", json={"publicKey": public_key(key)},
                               headers={config.TOKEN_HEADER: token})


def test_the_shared_vector_verifies_so_both_sides_agree_on_the_encoding():
    """The Swift tests read this same file: base64 x963 key, base64 payload bytes, base64 DER."""
    held = json.loads(VECTOR.read_text())
    said = proofs.verify(held["publicKey"], held["payload"], held["signature"])
    assert said == json.loads(held["payloadText"])
    assert len(base64.b64decode(held["publicKey"])) == proofs.KEY_BYTES
    assert base64.b64decode(held["payload"]) == held["payloadText"].encode()


def test_a_signature_over_other_bytes_or_by_another_key_does_not_verify():
    key, other = ec.generate_private_key(ec.SECP256R1()), ec.generate_private_key(ec.SECP256R1())
    proof = signed(key, v=1, value={"answer": True})
    assert proofs.verify(public_key(key), proof["payload"], proof["signature"]) is not None
    assert proofs.verify(public_key(other), proof["payload"], proof["signature"]) is None
    flipped = b64(b'{"v":1,"value":{"answer":false}}')
    assert proofs.verify(public_key(key), flipped, proof["signature"]) is None
    assert proofs.verify(public_key(key), "not base64!", proof["signature"]) is None


def test_the_fingerprint_is_the_first_eight_bytes_of_the_keys_sha256():
    key = ec.generate_private_key(ec.SECP256R1())
    raw = base64.b64decode(public_key(key))
    assert len(proofs.fingerprint(raw)) == 16
    assert proofs.key_from(public_key(key)) == raw
    assert proofs.key_from(b64(b"\x04" + b"\x00" * 64)) is None


def test_a_paired_phone_files_its_key_and_the_same_key_again_is_fine(claude_home, key):
    token, _ = devices.mint("JJ's iPhone", "phone")
    first = put_key(token, key)
    again = put_key(token, key)

    assert first.status_code == again.status_code == 200
    assert first.json() == again.json() == {"registered": True,
                                            "fingerprint": first.json()["fingerprint"]}
    row = devices.known(token)
    assert row["key"] == public_key(key) and row["fingerprint"] == first.json()["fingerprint"]
    read = TestClient(app).get("/devices/key", headers={config.TOKEN_HEADER: token}).json()
    assert read == {"registered": True, "fingerprint": row["fingerprint"]}


def test_the_first_key_wins_and_another_takes_a_re_pair(claude_home, key):
    token, _ = devices.mint("JJ's iPhone", "phone")
    put_key(token, key)
    swapped = put_key(token, ec.generate_private_key(ec.SECP256R1()))

    assert swapped.status_code == 409
    assert swapped.json()["detail"]["code"] == "KEY_TAKEN"
    assert devices.known(token)["key"] == public_key(key)


def test_this_macs_own_token_cannot_file_a_key(claude_home, key):
    """Every agent on the Mac can read that token, so a key filed with it proves nothing."""
    refused = put_key(config.token(), key)
    assert refused.status_code == 403
    assert refused.json()["detail"]["code"] == "NOT_A_DEVICE"


def test_a_scoped_token_cannot_file_a_key(claude_home, key):
    token, _ = devices.mint("browser", TRANSCRIBE, scope=TRANSCRIBE)
    refused = put_key(token, key)
    assert refused.status_code == 403
    assert refused.json()["detail"]["code"] == "NOT_A_DEVICE"


def test_a_key_that_is_not_a_p256_point_is_refused(claude_home):
    token, _ = devices.mint("JJ's iPhone", "phone")
    bad = TestClient(app).put("/devices/key", json={"publicKey": b64(b"\x04" + b"\x01" * 64)},
                              headers={config.TOKEN_HEADER: token})
    assert bad.status_code == 400 and bad.json()["detail"]["code"] == "BAD_KEY"


def test_a_phone_with_no_key_reads_as_not_registered(claude_home):
    token, _ = devices.mint("JJ's iPhone", "phone")
    read = TestClient(app).get("/devices/key", headers={config.TOKEN_HEADER: token}).json()
    assert read == {"registered": False, "fingerprint": None}
