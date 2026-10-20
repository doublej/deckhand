"""The addresses in a session's transcript and its subagents', one row per place they point at.

**One row per origin, not per string.** `localhost:5173`, `http://127.0.0.1:5173/admin` and
`0.0.0.0:5173` are one server, and a list that showed them as three would be three rows to check
and read where one answers. The paths it was named with ride along under the row.

Three shapes are looked for: full URLs, bare IPv4 addresses (with or without a port), and bare
domain names — but only under a short list of endings. A transcript is mostly code, and in code
`self.page`, `expect(x).to.be` and `Deckhand.app` are all "domains" to a pattern that takes any
ending, so the endings that collide with code are left to the URL pattern, which still finds
them whenever a scheme is written.

**How it was named is kept, because it is most of what makes one matter.** Three ways, from
most to least chosen: *shared* (in prose — an agent telling the person, or the person's own
words), *used* (in a tool call the session made: a `curl`, a `WebFetch`) and *printed* (in what
a tool handed back, which is how a URL inside some old file arrives — or in a file the session
wrote, a heredoc included, whose URLs are content rather than somewhere it went). `ranking.py` turns that,
how recent it is and atlas's word into the order the phone shows.

Read incrementally (`reading/increments.py`): a transcript's window once, then only what was
appended, with megabyte-long lines skipped unread.
"""

from __future__ import annotations

import ipaddress
import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlsplit

from ..reading.increments import Increments, subagents
from ..reading.transcripts import TAIL_WINDOWS, transcript_path

# A backslash ends a URL because the line is raw JSON: `\n`, `\"` and `<` are escapes.
URL = re.compile(r"\bhttps?://[^\s\"'<>\\`{}|^\[\]]+", re.IGNORECASE)
IPV4 = re.compile(r"(?<![\w.:/])((?:\d{1,3}\.){3}\d{1,3})(?::(\d{2,5}))?(?![\w/]|\.\d)")
LOCALHOST = re.compile(r"(?<![\w./-])localhost:(\d{2,5})\b", re.IGNORECASE)
ENDINGS = "com|net|org|io|dev|ai|co|nl|eu|uk|xyz|local"
DOMAIN = re.compile(
    r"(?<![\w.@/-])((?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+(?:" + ENDINGS + r"))"
    r"(?::(\d{2,5}))?(?![\w-]|\.\w)",
    re.IGNORECASE,
)
# Names that are never a place anybody meant to go.
NOISE = re.compile(r"(^|\.)(example\.(com|org|net)|w3\.org|json-schema\.org|schemas\.\w+\.\w+"
                   r"|cloudflareaccess\.com)$")
# The documentation ranges: an address written to stand for one, never one anybody serves on.
TEST_NETS = tuple(ipaddress.ip_network(n) for n in ("192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24"))
LOOPBACK = {"localhost", "127.0.0.1", "0.0.0.0", "::1"}
SUBAGENTS = 30
WRITES = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
PATHS = 5
MAX_ROWS = 60


@dataclass(slots=True)
class Found:
    """One origin and everything known about how it was named."""

    origin: str
    kind: str  # url | ip | domain — the most specific shape it was ever written in
    paths: list[str] = field(default_factory=list)
    mentions: int = 0
    #: The newest time it was named at all, and the newest time it was shared in prose / used in
    #: a tool call — ISO timestamps, empty for never.
    last_at: str = ""
    shared_at: str = ""
    used_at: str = ""
    in_agents: bool = False

    @property
    def said(self) -> bool:
        return bool(self.shared_at or self.used_at)

    def to_json(self) -> dict:
        return {"origin": self.origin, "kind": self.kind, "paths": self.paths,
                "mentions": self.mentions, "said": self.said, "in_agents": self.in_agents,
                "last_at": self.last_at, "shared_at": self.shared_at}


Seen = tuple[str, str, str, str, str]  # origin, kind, path, at, how: shared | used | printed
KEEP = 20_000


def _scan(raw: bytes, _: object) -> list[Seen]:
    return _in_entry(raw)


#: The session's own transcript over the 4 MB window the files tab reads; a subagent's over
#: 512 KB, since thirty of them at 4 MB would be the expensive half of every first open.
_session: Increments[Seen] = Increments(_scan, TAIL_WINDOWS[1], KEEP)
_agents: Increments[Seen] = Increments(_scan, TAIL_WINDOWS[0], KEEP)


def mentioned(session_id: str) -> list[Found]:
    """Every origin the session and its newest subagents named, chosen ones first."""
    path = transcript_path(session_id)
    if path is None:
        return []
    rows: dict[str, Found] = {}
    seen = [(_session.read(path), False), *((_agents.read(agent), True) for agent in subagents(path, SUBAGENTS))]
    for found, in_agent in seen:
        for origin, kind, where, at, how in found:
            row = rows.setdefault(origin, Found(origin, kind))
            row.mentions += 1
            row.in_agents |= in_agent
            row.last_at = max(row.last_at, at)
            if how == "shared":
                row.shared_at = max(row.shared_at, at)
            elif how == "used":
                row.used_at = max(row.used_at, at)
            if kind == "url":
                row.kind = "url"
            if where and where not in row.paths:
                row.paths.append(where)
    for row in rows.values():
        row.paths = row.paths[-PATHS:][::-1]  # newest first
    ordered = sorted(rows.values(), key=lambda r: (r.said, r.last_at), reverse=True)
    return ordered[:MAX_ROWS]


def active(session_id: str) -> float:
    """When the session last wrote anything — what `ranking` measures "recent" from."""
    path = transcript_path(session_id)
    return _mtime(path) if path else 0.0


def _mtime(path: Path) -> float:
    try:
        return path.stat().st_mtime
    except OSError:
        return 0.0


def _in_entry(raw: bytes) -> list[Seen]:
    """Every address in one transcript line, if the line is a conversation entry at all.

    Attachments, summaries and injected meta entries are left out: they are the same CLAUDE.md
    and reminders in every session, and every session listing the same ten addresses is noise.
    """
    try:
        entry = json.loads(raw)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return []
    if not isinstance(entry, dict) or entry.get("type") not in ("user", "assistant") \
            or entry.get("isMeta"):
        return []
    at = str(entry.get("timestamp") or "")
    return [(origin, kind, where, at, how) for how, text in _pieces(entry)
            for origin, kind, where in found_in(text)]


def _pieces(entry: dict) -> list[tuple[str, str]]:
    """(how, text) for each part of an entry: prose is shared, a tool call used, a result printed.
    A tool's input and output are scanned as JSON text, where a backslash ends a URL as in the raw line."""
    content = (entry.get("message") or {}).get("content")
    if isinstance(content, str):
        return [("shared", content)]
    out = []
    for block in content if isinstance(content, list) else []:
        kind = block.get("type") if isinstance(block, dict) else None
        if kind == "text":
            out.append(("shared", str(block.get("text") or "")))
        elif kind == "tool_use":
            body = json.dumps(block.get("input"))
            # Writing a file is not going anywhere: the URLs in a test fixture are content.
            wrote = block.get("name") in WRITES or (block.get("name") == "Bash" and "<<" in body)
            out.append(("printed" if wrote else "used", body))
        elif kind == "tool_result":
            out.append(("printed", json.dumps(block.get("content"))))
    return out


def found_in(text: str) -> list[tuple[str, str, str]]:
    """(origin, kind, path) for every address in a piece of text, in the order written."""
    out = []
    for match in URL.finditer(text):
        if hit := _from_url(match.group(0).rstrip(".,;:!?*)")):
            out.append(hit)
    rest = URL.sub(" ", text)
    for match in IPV4.finditer(rest):
        host, port = match.group(1), match.group(2)
        try:
            ip = ipaddress.ip_address(host)
        except ValueError:
            continue
        # Without a port, a loopback, a netmask, 0.0.0.0 or a network's .0 is configuration.
        quiet = ip.is_loopback or ip.is_unspecified or host.startswith("255.") or host.endswith(".0")
        if (port or not quiet) and not any(ip in net for net in TEST_NETS):
            out.append((_origin("http", host, port), "ip", ""))
    for match in LOCALHOST.finditer(rest):
        out.append((_origin("http", "localhost", match.group(1)), "ip", ""))
    for match in DOMAIN.finditer(rest):
        host, port = match.group(1).lower(), match.group(2)
        if not NOISE.search(host):
            scheme = "http" if host.endswith(".local") or (port and port != "443") else "https"
            out.append((_origin(scheme, host, port), "domain", ""))
    return out


def _from_url(url: str) -> tuple[str, str, str] | None:
    try:
        parts = urlsplit(url)
        host, port = parts.hostname, parts.port
    except ValueError:
        return None
    if not host or NOISE.search(host):
        return None
    where = parts.path + (f"?{parts.query}" if parts.query else "")
    return _origin(parts.scheme.lower(), host, str(port) if port else None), "url", \
        "" if where == "/" else where


def _origin(scheme: str, host: str, port: str | None) -> str:
    """scheme://host[:port], with every name for this machine spelled `localhost` and a
    default port left off — so the three spellings of one server are one row."""
    host = "localhost" if host.lower() in LOOPBACK else host.lower()
    default = {"http": "80", "https": "443"}[scheme]
    return f"{scheme}://{host}" + (f":{port}" if port and port != default else "")
