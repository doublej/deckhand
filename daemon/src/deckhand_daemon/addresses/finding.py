"""The addresses in a session's transcript and its subagents', one row per place they point at.

**One row per origin, not per string.** `localhost:5173`, `http://127.0.0.1:5173/admin` and
`0.0.0.0:5173` are one server, and a list that showed them as three would be three rows to check
and read where one answers. The paths it was named with ride along under the row.

Three shapes are looked for: full URLs, bare IPv4 addresses (with or without a port), and bare
domain names — but only under a short list of endings. A transcript is mostly code, and in code
`self.page`, `expect(x).to.be` and `Deckhand.app` are all "domains" to a pattern that takes any
ending, so the endings that collide with code are left to the URL pattern, which still finds
them whenever a scheme is written.

**What the session said beats what a tool printed.** A fetched docs page carries forty links
nobody chose; the address a session typed into a command, or the person spoke, was chosen. Each
row says whether it was ever *said* (an assistant entry, or the person's own words) and the
list puts those first, newest first within each half.

Read from the transcript's last 4 MB and each subagent's, the window the files tab reads, and
kept per file until the file changes — the same deal `files._named` makes.
"""

from __future__ import annotations

import ipaddress
import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlsplit

from ..reading.transcripts import TAIL_WINDOWS, tail_lines, transcript_path

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
PATHS = 5
MAX_ROWS = 40


@dataclass(slots=True)
class Found:
    """One origin and everything known about how it was named."""

    origin: str
    kind: str  # url | ip | domain — the most specific shape it was ever written in
    paths: list[str] = field(default_factory=list)
    mentions: int = 0
    said: bool = False
    in_agents: bool = False
    last_at: str = ""

    def to_json(self) -> dict:
        return {"origin": self.origin, "kind": self.kind, "paths": self.paths,
                "mentions": self.mentions, "said": self.said, "in_agents": self.in_agents,
                "last_at": self.last_at}


#: transcript -> ((size, mtime), what it names). One seen tuple: (origin, kind, path, at, said).
_kept: dict[Path, tuple[tuple[int, int], list[tuple[str, str, str, str, bool]]]] = {}


def mentioned(session_id: str) -> list[Found]:
    """Every origin the session and its newest subagents named, chosen ones first."""
    path = transcript_path(session_id)
    if path is None:
        return []
    # Where `reading/agents.py` finds them: a folder named after the transcript, beside it.
    agents = sorted((path.with_suffix("") / "subagents").glob("*.jsonl"), key=_mtime,
                    reverse=True)[:SUBAGENTS]
    rows: dict[str, Found] = {}
    for source, in_agent in [(path, False), *((agent, True) for agent in agents)]:
        for origin, kind, where, at, said in _seen(source):
            row = rows.setdefault(origin, Found(origin, kind))
            row.mentions += 1
            row.said |= said
            row.in_agents |= in_agent
            row.last_at = max(row.last_at, at)
            if kind == "url":
                row.kind = "url"
            if where and where not in row.paths:
                row.paths.append(where)
    for row in rows.values():
        row.paths = row.paths[-PATHS:][::-1]  # newest first
    ordered = sorted(rows.values(), key=lambda r: (r.said, r.last_at), reverse=True)
    return ordered[:MAX_ROWS]


def _mtime(path: Path) -> float:
    try:
        return path.stat().st_mtime
    except OSError:
        return 0.0


def _seen(path: Path) -> list[tuple[str, str, str, str, bool]]:
    try:
        stat = path.stat()
    except OSError:
        return []
    key = (stat.st_size, stat.st_mtime_ns)
    kept = _kept.get(path)
    if kept is None or kept[0] != key:
        kept = _kept[path] = (key, [hit for raw in tail_lines(path, TAIL_WINDOWS[1])
                                    for hit in _in_entry(raw)])
    return kept[1]


def _in_entry(raw: bytes) -> list[tuple[str, str, str, str, bool]]:
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
    content = (entry.get("message") or {}).get("content")
    printed = isinstance(content, list) and any(
        isinstance(block, dict) and block.get("type") == "tool_result" for block in content)
    said = entry["type"] == "assistant" or not printed
    at = str(entry.get("timestamp") or "")
    return [(origin, kind, where, at, said) for origin, kind, where in found_in(raw.decode("utf-8", "replace"))]


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
