"""Whether an address loads, whether it wants a password, and from where it can be opened.

**Where it can be opened from is the question the phone actually has.** `reach` is one of
`mac` (only this Mac), `home` (anything on the home network), `public` (anywhere) or `none` (the
name does not resolve). A loopback address that also answers on this Mac's LAN address is
`home`, with that address in `lan_url` — which is what turns `localhost:5173` into a link that
opens on the phone. `public` means the name resolves to a public address; nothing here can
stand outside the house to prove it loads from there.

**A probe is one GET, and only ever of the origin or a path the session wrote.** A path carrying
something that looks like a key (`?token=`, `?code=`, a signature) is never requested — a magic
link is spent by being opened — so the origin's root is asked instead. Nothing is sent but a
user agent: no cookie, no token, no body. At most 64 kB is read, for the title and a password
field.

Kept per URL for two minutes, and a check that outlasts the route's budget goes on in the
background and lands in the cache, so the phone's next poll has it.
"""

from __future__ import annotations

import asyncio
import html
import ipaddress
import re
import socket
import time
from dataclasses import asdict, dataclass
from urllib.parse import urlsplit

import httpx

from .. import config

FRESH = 120.0
BUDGET = 4.0
TIMEOUT = 3.0
RESOLVE_TIMEOUT = 2.0
READ = 64 * 1024
AT_ONCE = 8
# Browser-shaped, so a site that turns away bare scripts answers the way it would answer a phone.
AGENT = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) deckhand-check"
TOKENED = re.compile(r"[?&](?:[\w-]*(?:token|key|code|sig|signature|secret|auth|session|password)"
                     r"[\w-]*)=", re.IGNORECASE)
LOGIN = re.compile(r"/(?:log-?in|sign-?in|auth|sso|oauth|account/login)\b", re.IGNORECASE)
PASSWORD_FIELD = re.compile(rb"type\s*=\s*[\"']?password", re.IGNORECASE)
TITLE = re.compile(rb"<title[^>]*>(.*?)</title>", re.IGNORECASE | re.DOTALL)


@dataclass(slots=True)
class Check:
    #: loads | locked (wants a password or refuses) | fails (an error page) | down (no answer)
    state: str
    reach: str = ""
    status: int = 0
    title: str = ""
    note: str = ""
    lan_url: str = ""

    def to_json(self) -> dict:
        return asdict(self)


_kept: dict[str, tuple[float, Check]] = {}
_running: dict[str, asyncio.Task] = {}
_gate = asyncio.Semaphore(AT_ONCE)


async def check_all(targets: dict[str, str]) -> dict[str, Check]:
    """{origin: check} for every {origin: path} given whose check finished inside the budget.
    An origin missing from the answer is still being checked."""
    now = time.monotonic()
    urls = {origin: _url(origin, where) for origin, where in targets.items()}
    for url in set(urls.values()):
        kept = _kept.get(url)
        if (kept is None or now - kept[0] > FRESH) and url not in _running:
            _running[url] = asyncio.create_task(_keep(url))
    if waiting := [_running[url] for url in set(urls.values()) if url in _running]:
        await asyncio.wait(waiting, timeout=BUDGET)
    return {origin: kept[1] for origin, url in urls.items() if (kept := _kept.get(url))}


def _url(origin: str, where: str) -> str:
    return origin + (where if where and not TOKENED.search(where) else "/")


async def _keep(url: str) -> None:
    try:
        async with _gate:
            _kept[url] = (time.monotonic(), await probe(url))
    finally:
        _running.pop(url, None)


async def probe(url: str) -> Check:
    host = urlsplit(url).hostname or ""
    reach = await _reach(host)
    if reach == "none":
        return Check("down", reach, note="the name does not resolve")
    check = await _fetch(url)
    check.reach = reach
    if reach == "mac" and check.state != "down" and (lan := config.lan_address()):
        moved = url.replace(f"//{host}", f"//{lan}", 1)
        if (await _fetch(moved)).state != "down":
            check.reach, check.lan_url = "home", moved
    return check


async def _reach(host: str) -> str:
    try:
        found = await asyncio.wait_for(asyncio.to_thread(socket.getaddrinfo, host, None),
                                       RESOLVE_TIMEOUT)
    except (OSError, TimeoutError):
        return "none"
    ips = {ipaddress.ip_address(info[4][0].split("%")[0]) for info in found}
    if all(ip.is_loopback or ip.is_unspecified for ip in ips):
        return "mac"
    # Not global covers the LAN, link-local and a tailnet's 100.64/10 alike.
    return "public" if any(ip.is_global for ip in ips) else "home"


async def _fetch(url: str) -> Check:
    """One GET, read no further than the title and a password field need."""
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT, follow_redirects=True,
                                     headers={"user-agent": AGENT}) as client, \
                client.stream("GET", url) as answer:
            body = b""
            async for chunk in answer.aiter_bytes():
                body += chunk
                if len(body) >= READ:
                    break
    except httpx.TimeoutException:
        return Check("down", note=f"no answer in {TIMEOUT:g} s")
    except httpx.RemoteProtocolError:
        return Check("down", note="answers, but not as a web server")
    except (httpx.HTTPError, OSError) as error:
        trust = "CERTIFICATE" in str(error).upper()
        return Check("down", note="its certificate is not trusted" if trust else "nothing answers")
    return _verdict(answer, body)


def _verdict(answer: httpx.Response, body: bytes) -> Check:
    """Locked means a person needs a password to get further — a 401, Cloudflare Access, or a
    redirect onto a login path. A login *form* on a page that loads is only a note: half the
    homepages on the internet carry one."""
    status, final = answer.status_code, answer.url
    title = TITLE.search(body)
    check = Check("loads", status=status,
                  title=html.unescape(title.group(1).decode("utf-8", "replace")).strip()[:80]
                  if title else "")
    if status in (401, 407):
        check.state, check.note = "locked", "asks for a password"
    elif "cloudflareaccess.com" in (final.host or ""):
        check.state, check.note = "locked", "behind Cloudflare Access"
    elif answer.history and LOGIN.search(final.path):
        check.state, check.note = "locked", "sends you to a login page"
    elif answer.headers.get("cf-mitigated") == "challenge":
        check.state, check.note = "loads", "behind a bot check — a browser gets through"
    elif status == 404 and final.path in ("", "/"):
        check.state, check.note = "loads", "up, with nothing at /"
    elif status >= 400:
        check.state, check.note = "fails", f"answers {status}"
    elif PASSWORD_FIELD.search(body):
        check.note = "has a login form"
    return check
