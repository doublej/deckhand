"""One ssh process per remote machine, which both forwards a port and runs the hand behind it.

```
ssh -L 419n:127.0.0.1:4181 <alias> 'exec deckhand-daemon --hand'
```

**One process does both jobs on purpose.** The hand's lifetime is the ssh connection's lifetime,
so there is no systemd unit on Ubuntu and no Scheduled Task on Fractal — nothing to install, and
nothing left running when this daemon stops. That is affordable only because a hand keeps no
state worth surviving: everything the person has set is on this Mac.

**The hand binds loopback, so nothing about a session's inbox is ever on the LAN.** No listening
port on Ubuntu or Fractal, no Windows firewall rule, and no token typed anywhere — the daemon
passes its own in the environment (`config.token`). Authentication is the key-only ssh mesh that
already works between these machines.

Two things here are inherited from atlas rather than rediscovered, both from `remoteScan.ts`:

- **`ConnectTimeout=4`, always.** A powered-off DHCP box otherwise hangs the TCP connect for
  around 75 seconds. Deckhand asks "is this machine up" on every session listing, so without this
  a sleeping Ubuntu stalls the phone's list for over a minute.
- **No `ControlMaster`.** Windows OpenSSH does not have it, which is why atlas never built
  connection reuse — and why one long-lived connection per machine is the only cheap shape going.

**Reachability is this link's own state, not a probe.** Atlas made the point and it removed a
moving part: the link being up *is* the machine being up, at no extra ssh cost. There is nothing
to poll and nothing to keep fresh.
"""

from __future__ import annotations

import os
import shlex
import subprocess
import time
from dataclasses import dataclass, field

from ..config import PORT, token
from ..log import log
from .registry import Machine

# A hand binds one past the daemon's port on its own machine; the forward lands on 4190 upward
# here, away from anything the daemon or a dev server would want.
HAND_PORT = PORT + 1
FIRST_LOCAL_PORT = PORT + 10
SSH_OPTIONS = [
    "-o", "BatchMode=yes",  # never prompt: there is nobody at this daemon to answer
    "-o", "ConnectTimeout=4",  # atlas's number, and its 75-second reason
    "-o", "ServerAliveInterval=15",  # notice a dropped link rather than holding a dead socket
    "-o", "ServerAliveCountMax=2",
    "-o", "ExitOnForwardFailure=yes",  # a forward that did not bind is a link that lies
]
# How long to keep a machine that will not come up out of the retry loop. A machine is usually
# down because it is off, and asking every few seconds only fills the log.
BACKOFF = (5.0, 15.0, 60.0, 300.0)


# Where a hand is installed on every machine, by convention rather than configuration — the same
# shape atlas uses for `~/.atlas`, and one less field to ask atlas to carry.
HAND_ROOT = "~/.deckhand"


def remote_command(machine: Machine, secret: str) -> str:
    """The line the hand starts with, and the one place the two shells differ.

    Fractal answers ssh with PowerShell, where `VAR=value cmd` is not a thing and `&` is not a
    separator — so the token goes in as `$env:` and the two statements are joined with `;`.

    `uv run` rather than a bare entry point: it is what `just install-hand` set up, and it means
    the hand runs on the Python its own lockfile pinned instead of whatever the machine's
    `python3` happens to be — 3.12 on Ubuntu, against a package that asks for 3.13.
    """
    if machine.os == "win32":
        return (
            f"$env:DECKHAND_TOKEN='{secret}'; $env:DECKHAND_MACHINE='{machine.id}'; "
            f"uv run --no-dev --directory $HOME/.deckhand deckhand-daemon --hand"
        )
    # `~/.local/bin` on PATH explicitly: that is where uv's installer puts it, and a
    # non-interactive ssh command does not read the profile that would have added it. The
    # failure without this is `command not found: uv`, which the link reports but cannot fix.
    run = f"uv run --no-dev --directory {HAND_ROOT} deckhand-daemon --hand"
    env = f"DECKHAND_TOKEN={shlex.quote(secret)} DECKHAND_MACHINE={shlex.quote(machine.id)}"
    return f'PATH="$HOME/.local/bin:$PATH" {env} exec {run}'


@dataclass
class Link:
    """The ssh process for one machine, and everything known about whether it is up."""

    machine: Machine
    port: int
    process: subprocess.Popen | None = None
    ready: bool = False
    error: str = ""
    attempts: int = 0
    next_try: float = 0.0
    _log: list[str] = field(default_factory=list)

    @property
    def alive(self) -> bool:
        return self.process is not None and self.process.poll() is None

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    def to_json(self) -> dict:
        """What `/machines` says about this one. `reachable` is the link, because the link being
        up is the machine being up."""
        return {
            "id": self.machine.id,
            "label": self.machine.label,
            "os": self.machine.os,
            "reachable": self.ready,
            "error": self.error,
            "primary": False,
        }


_links: dict[str, Link] = {}


def links() -> dict[str, Link]:
    """Every remote machine's link, made on first ask. The primary has none: it is this Mac."""
    from .registry import machines

    for index, machine in enumerate(m for m in machines() if not m.is_primary):
        if machine.id not in _links:
            _links[machine.id] = Link(machine=machine, port=FIRST_LOCAL_PORT + index)
    return _links


def start(link: Link) -> bool:
    """Spawn the ssh process, and say whether there is now one to wait for.

    Does not wait for the hand behind it to bind — `ready` is set by whoever polls `/health`,
    because the forward is up well before the process is listening.

    **False means "still serving a backoff", and the caller must do nothing else.** Every
    `went_down` pushes the next attempt further out, so a caller that went on to fail a machine
    it never actually tried would push it out again — and with a phone polling every few seconds
    that arithmetic never lets the retry fire at all. A machine that dropped overnight then
    stayed unreachable for as long as anyone was watching, which is the worst possible time.
    """
    if link.alive:
        return True
    if time.monotonic() < link.next_try:
        return False
    command = [
        "ssh", *SSH_OPTIONS,
        "-L", f"{link.port}:127.0.0.1:{HAND_PORT}",
        link.machine.ssh or link.machine.id,
        remote_command(link.machine, token()),
    ]
    try:
        # stdout and stderr are the hand's own log; kept rather than dropped so a machine that
        # will not start says why instead of merely failing to appear.
        link.process = subprocess.Popen(
            command,
            # A pipe, and held open for the life of the link: it is what the hand watches to
            # know this link is gone (`hand._die_with_the_link`). Inheriting the daemon's own
            # stdin would be worse than useless — under launchd that is `/dev/null`, which is
            # EOF at once, and every hand would exit the moment it started.
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
            env=os.environ | {"DECKHAND_TOKEN": token()},
        )
    except OSError as error:
        link.error = f"cannot run ssh: {error}"
        _back_off(link)
        return False
    link.error = ""
    log.info("link to %s opening on 127.0.0.1:%d", link.machine.id, link.port)
    return True


# ssh writes advisory banners to stderr, which is merged into stdout here so a failing machine
# can say why. The post-quantum notice fires on every connection to an older sshd and is not a
# failure at all — left in, it becomes the reason the phone shows for a machine being down, and
# the real reason two lines below it is never seen.
NOISE = ("** ", "WARNING:", "post-quantum", "store now", "may need to be upgraded")


def useful_error(text: str) -> str:
    """What actually went wrong, out of everything ssh had to say about it."""
    lines = [
        line.strip()
        for line in text.splitlines()
        if line.strip() and not any(n in line for n in NOISE)
    ]
    return lines[-1][:200] if lines else "ssh exited without saying why"


def _back_off(link: Link) -> None:
    link.ready = False
    link.next_try = time.monotonic() + BACKOFF[min(link.attempts, len(BACKOFF) - 1)]
    link.attempts += 1


def went_down(link: Link, why: str) -> None:
    """Mark a link unusable and schedule the next attempt. Called when the ssh process exits or
    when the hand stops answering — both are the same thing to anyone upstream."""
    if link.ready or not link.error:
        log.warning("link to %s down: %s", link.machine.id, why)
    link.error = why
    _back_off(link)


def came_up(link: Link) -> None:
    if not link.ready:
        log.info("link to %s up", link.machine.id)
    link.ready = True
    link.error = ""
    link.attempts = 0


def stop(link: Link) -> None:
    if link.process is not None and link.alive:
        link.process.terminate()
    link.process = None
    link.ready = False


def stop_all() -> None:
    """Every hand dies with its link, which is the whole reason nothing has to be installed."""
    for link in _links.values():
        stop(link)
