"""The ssh line a hand starts with, and the two things about it that were wrong when first run
against a real machine. Both were silent, and both are asserted here rather than remembered."""

from __future__ import annotations

import pytest

from deckhand_daemon.fleet import link, registry

UBUNTU = registry.Machine(
    id="ubuntu", label="Ubuntu", ssh="ubuntu", root="/home/j", os="linux", role="deploy"
)
FRACTAL = registry.Machine(
    id="fractal", label="Fractal", ssh="fractal", root="C:/dev", os="win32", role="satellite"
)


def test_the_machine_is_named_by_the_daemon_not_guessed_at():
    """A hand has no atlas of its own, so without being told it falls back to its hostname —
    `mbp-ubuntu` where atlas says `ubuntu`. Every session it listed was then stamped with a
    machine the daemon could not route back to, and the listing looked perfectly fine."""
    assert "DECKHAND_MACHINE=ubuntu" in link.remote_command(UBUNTU, "tok")
    assert "$env:DECKHAND_MACHINE='fractal'" in link.remote_command(FRACTAL, "tok")


def test_uv_is_reached_by_an_explicit_path_on_posix():
    """A non-interactive ssh command does not read the profile that puts `~/.local/bin` on PATH,
    so the first real run died with `command not found: uv`."""
    assert 'PATH="$HOME/.local/bin:$PATH"' in link.remote_command(UBUNTU, "tok")


def test_the_token_is_passed_rather_than_minted_there():
    assert "DECKHAND_TOKEN=s3cret" in link.remote_command(UBUNTU, "s3cret")
    assert "$env:DECKHAND_TOKEN='s3cret'" in link.remote_command(FRACTAL, "s3cret")


def test_powershell_gets_semicolons_and_never_an_env_prefix():
    """Fractal answers ssh with PowerShell, where `VAR=value cmd` is not a thing."""
    line = link.remote_command(FRACTAL, "tok")
    assert "exec " not in line
    assert line.count(";") == 2


@pytest.mark.parametrize("option", ["BatchMode=yes", "ConnectTimeout=4", "ExitOnForwardFailure=yes"])
def test_the_ssh_options_atlas_paid_for(option):
    """`ConnectTimeout` above all: a powered-off DHCP box otherwise hangs the TCP connect for
    ~75 s, and this daemon asks whether a machine is up on every session listing."""
    assert option in link.SSH_OPTIONS


def test_a_machine_id_with_a_space_cannot_break_out_of_the_line():
    """The registry is hand-editable, so its values are input, not constants."""
    odd = registry.Machine(
        id="a b; rm -rf /", label="x", ssh="h", root="/", os="linux", role="deploy"
    )
    line = link.remote_command(odd, "tok")
    assert "; rm -rf /" not in line.replace("'a b; rm -rf /'", "")


def test_each_remote_machine_gets_its_own_port_and_the_primary_gets_none(monkeypatch, tmp_path):
    import json

    path = tmp_path / "hosts.json"
    path.write_text(
        json.dumps(
            {
                "hosts": [
                    {"id": "m2", "ssh": None},
                    {"id": "ubuntu", "ssh": "ubuntu"},
                    {"id": "fractal", "ssh": "fractal"},
                ]
            }
        )
    )
    monkeypatch.setenv("DECKHAND_ATLAS_REGISTRY", str(path))
    monkeypatch.setattr(link, "_links", {})
    made = link.links()
    assert set(made) == {"ubuntu", "fractal"}, "the primary is this Mac; it needs no link"
    assert len({one.port for one in made.values()}) == 2, "two machines cannot share one port"


class TestABackoffThatCanActuallyExpire:
    """The failure this class exists for was measured on 2026-09-12, not imagined.

    Ubuntu's ssh link died overnight. The next morning, with the phone open and polling every
    few seconds, `/machines` said it was unreachable and went on saying it — because every poll
    called `went_down` for an attempt that had never been made, and every one of those pushed
    the next attempt 300 seconds further away. The retry could only fire while nobody was
    looking, which is the one time it is no use.
    """

    @pytest.fixture
    def down(self, monkeypatch):
        one = link.Link(machine=UBUNTU, port=4191)
        link.went_down(one, "the machine went to sleep")
        monkeypatch.setattr(link.subprocess, "Popen", lambda *a, **k: pytest.fail("spawned ssh"))
        return one

    def test_a_link_serving_its_backoff_says_it_did_not_start(self, down):
        assert link.start(down) is False

    def test_asking_again_does_not_move_the_next_attempt(self, down):
        """The whole bug in one assertion: the wait may not grow when nothing was tried."""
        was = down.next_try
        for _ in range(20):
            link.start(down)
        assert down.next_try == was

    def test_the_wait_expires_and_the_link_tries_again(self, down, monkeypatch):
        spawned: list[list[str]] = []
        monkeypatch.setattr(link.subprocess, "Popen", lambda cmd, **k: spawned.append(cmd))
        monkeypatch.setattr(link.time, "monotonic", lambda: down.next_try + 1)

        assert link.start(down) is True
        assert spawned and "-L" in spawned[0]

    def test_a_link_already_up_is_started_without_spawning_a_second_one(self, monkeypatch):
        one = link.Link(machine=UBUNTU, port=4191)
        monkeypatch.setattr(link.subprocess, "Popen", lambda *a, **k: pytest.fail("spawned ssh"))
        monkeypatch.setattr(type(one), "alive", property(lambda self: True))

        assert link.start(one) is True


class TestACallThatFindsAMachineBackedOff:
    """Where the 2026-09-12 failure actually lived: `call` went on to `ready` a link `start` had
    refused to spawn, and `ready` failed it — which is the push that made the wait immortal."""

    @pytest.fixture
    def down(self, monkeypatch):
        one = link.Link(machine=UBUNTU, port=4191)
        link.went_down(one, "the machine went to sleep")
        monkeypatch.setattr(link, "_links", {"ubuntu": one})
        monkeypatch.setattr(link.subprocess, "Popen", lambda *a, **k: pytest.fail("spawned ssh"))
        return one

    def test_it_answers_absent_without_touching_the_wait(self, down):
        import asyncio

        from deckhand_daemon.fleet import proxy

        was = down.next_try
        for _ in range(20):
            assert asyncio.run(proxy.call("ubuntu", "GET", "/sessions")) is None
        assert down.next_try == was, "a call that tried nothing must not push the next attempt"


class TestTheLinkIsDrained:
    """A pipe nobody reads is a fuse: ssh's stdout holds 64 KB here, the hand writes into it on
    every log line, and a full buffer blocks ssh's own write — which from the daemon's side is a
    machine that stopped answering."""

    def _drained(self, lines):
        import io
        import time

        one = link.Link(machine=UBUNTU, port=4191)
        one.process = type("P", (), {"stdout": io.StringIO("".join(f"{x}\n" for x in lines))})()
        link._drain(one)
        for _ in range(200):
            if len(one._log) >= min(len(lines), link.KEPT_LINES):
                break
            time.sleep(0.005)
        return one

    def test_the_output_is_read_rather_than_left_in_the_pipe(self):
        one = self._drained(["opening", "hand on ubuntu"])
        assert link.said(one) == "opening\nhand on ubuntu"

    def test_only_the_last_lines_are_kept(self):
        """Bounded, or draining the pipe would only move the unbounded growth into this process."""
        one = self._drained([f"line {n}" for n in range(link.KEPT_LINES * 3)])
        assert len(one._log) == link.KEPT_LINES
        assert one._log[-1] == f"line {link.KEPT_LINES * 3 - 1}"

    def test_what_went_wrong_is_still_the_last_useful_line(self):
        """`useful_error` reads the drained lines now instead of the pipe, and its own rule about
        ssh's post-quantum banner has to go on holding."""
        one = self._drained(["** WARNING: post-quantum", "ubuntu: Connection refused"])
        assert link.useful_error(link.said(one)) == "ubuntu: Connection refused"
