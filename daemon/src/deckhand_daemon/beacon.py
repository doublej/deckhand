"""Say on the local network where this Mac answers, so the phone need not be told.

The advertisement is one `dns-sd -R` held open as a child of this process. mDNS registration
lives exactly as long as that process, so there is no unregister to get wrong and nothing left
behind when the daemon is killed rather than stopped — which is the common case here, since the
launchd agent is bounced with `kickstart -k` several times a day.

The child is deliberately left in this process's own group, and that is what makes the killed
case safe: measured on 2026-09-14, the `dns-sd` comes up with the parent's own pgid, and a
`kill -KILL` sent to that group takes both. launchd signals a job's group, and so does Ctrl-C in
`just daemon`. The one path that does leak — also measured — is a signal sent to the daemon's
pid *alone*, which kills the parent before `stop` runs and leaves the child advertising. The
phone's reading of that is one row offering an address that will not answer, and the next start
re-registers over it, so this is a ceiling rather than a bug to defend against here.

**Both addresses come out of `config`, and neither is worked out again here.** `/health` already
publishes `host` and `lan`, and this is the same question asked in a second place — two answers
to one question is how they come apart, which is the argument `settings/routes.for_project`
makes for resolving a folder's switches on the Mac rather than on the phone.

**The token is never in here.** mDNS is an unauthenticated broadcast to everything on the LAN,
and that token is the only thing in front of every route but `/health`. A beacon answers *where*
the Mac is; the pairing code is still typed once, by hand, exactly as before.

Not a dependency: `dns-sd` ships with macOS (`/usr/bin/dns-sd`, mDNSResponder 2881.160.4 here).
A machine without it — a hand on Linux or Windows, which runs `fleet/hand.py` and never this
lifespan anyway — simply does not advertise, and says so once in the log. Nothing here may keep
the daemon from starting.
"""

from __future__ import annotations

import shutil
import socket
import subprocess
from urllib.parse import urlsplit

from . import __version__
from .config import PORT, base_url, lan_address
from .log import log

SERVICE = "_deckhand._tcp"
#: How long `stop` waits for the child before insisting.
GOODBYE = 2.0

_process: subprocess.Popen | None = None


def machine_name() -> str:
    """This Mac as the phone will list it: the hostname without the mDNS suffix."""
    return socket.gethostname().removesuffix(".local") or "deckhand"


def command() -> list[str]:
    """The whole registration, as argv.

    Its own function because these TXT keys are a contract with `Beacon.read` on the phone, and
    a contract nothing can assert is a contract that drifts.

    Two addresses, in preference order, and both carry their port — the `.local` name first
    because it survives DHCP, and the raw IP behind it because mDNS name resolution is not
    something this Mac can promise on every link it finds itself on. Measured 2026-09-14: `lan`
    was `172.20.10.8`, an iPhone personal-hotspot range, which is exactly the day a hardcoded
    address would have been wrong. An address that cannot be worked out at all is left out
    rather than advertised empty: absence is a key the phone never sees.
    """
    txt = [f"host={urlsplit(base_url()).netloc}", "name=deckhand", f"version={__version__}"]
    if lan := lan_address():
        txt.append(f"lan={lan}:{PORT}")
    return ["dns-sd", "-R", machine_name(), SERVICE, "local", str(PORT), *txt]


def start() -> None:
    """Begin advertising. A missing or unhappy `dns-sd` is a log line, never a failed start."""
    global _process
    if _process is not None:
        return
    argv = command()
    found = shutil.which(argv[0])
    if found is None:
        log.info("no %s on this machine; not advertising %s", argv[0], SERVICE)
        return
    try:
        _process = subprocess.Popen(
            [found, *argv[1:]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    except OSError as error:
        log.warning("could not advertise %s: %s", SERVICE, error)
        return
    log.info("advertising %s as %s on port %d", SERVICE, machine_name(), PORT)


def stop() -> None:
    """Take the advertisement down. Only ever reached on a clean shutdown; a hard one is the
    process group going, which takes the child with it."""
    global _process
    if _process is None:
        return
    process, _process = _process, None
    process.terminate()
    try:
        process.wait(timeout=GOODBYE)
    except subprocess.TimeoutExpired:
        process.kill()
