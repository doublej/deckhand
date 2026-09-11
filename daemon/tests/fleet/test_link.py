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
