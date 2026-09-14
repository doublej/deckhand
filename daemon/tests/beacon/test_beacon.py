"""The advertisement is a contract with the phone, so it is asserted rather than eyeballed."""

from __future__ import annotations

import subprocess
from urllib.parse import urlsplit

from deckhand_daemon import __version__, beacon
from deckhand_daemon.config import PORT, base_url, lan_address


def keys(argv: list[str]) -> dict[str, str]:
    return dict(part.split("=", 1) for part in argv if "=" in part)


def test_the_registration_carries_the_keys_the_phone_reads() -> None:
    """`Beacon.read` on the phone takes the address out of `host`, falls back to `lan`, and
    ignores the rest — so these names are a wire contract and not a detail of this file."""
    argv = beacon.command()
    assert argv[:2] == ["dns-sd", "-R"]
    assert argv[2] == beacon.machine_name()
    assert argv[3:6] == [beacon.SERVICE, "local", str(PORT)]
    said = keys(argv)
    assert said["name"] == "deckhand"
    assert said["version"] == __version__
    assert said["host"] == urlsplit(base_url()).netloc


def test_both_addresses_are_the_ones_health_publishes() -> None:
    """Not recomputed here. `/health` answers `host` and `lan` from the same two functions, and
    two answers to one question is how they come apart."""
    said = keys(beacon.command())
    assert said["host"].startswith(urlsplit(base_url()).hostname or "")
    assert said["host"].endswith(f":{PORT}")
    if address := lan_address():
        assert said["lan"] == f"{address}:{PORT}"
    else:
        assert "lan" not in said


def test_an_address_that_cannot_be_worked_out_is_left_out(monkeypatch) -> None:
    """An empty `lan=` would be a key the phone has to learn to disbelieve."""
    monkeypatch.setattr(beacon, "lan_address", lambda: "")
    assert "lan" not in keys(beacon.command())


def test_the_token_is_never_advertised(monkeypatch) -> None:
    """mDNS is an unauthenticated broadcast to the whole LAN and the pairing token is the only
    thing in front of every route but /health. Asserted against the secret itself rather than
    against the word `token`, so a key spelled anything at all still cannot carry it."""
    secret = "pineapple-1234"
    monkeypatch.setenv("DECKHAND_TOKEN", secret)
    assert not any(secret in part for part in beacon.command())


def test_a_machine_without_dns_sd_starts_anyway(monkeypatch) -> None:
    """Nothing here may keep the daemon from coming up: a hand on Linux has no `dns-sd`."""
    monkeypatch.setattr(beacon.shutil, "which", lambda _: None)
    monkeypatch.setattr(beacon, "_process", None)

    def refuse(*args, **kwargs):
        raise AssertionError("nothing should be started without dns-sd")

    monkeypatch.setattr(subprocess, "Popen", refuse)
    beacon.start()
    assert beacon._process is None
    beacon.stop()
