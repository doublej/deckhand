"""What a pattern is, and which bindings a page URL belongs to. No disk, no HTTP.

A pattern is normalised once, on the way in, so two spellings of one page are one binding:
`https://Example.com/docs/` and `https://example.com/docs` must never be stored as two.
"""

from __future__ import annotations

from urllib.parse import urlsplit


def split(url: str) -> tuple[str, str]:
    """An http(s) URL with a host as (origin, path), or ValueError.

    The origin is scheme, host and port: `urlsplit` already lowercases the scheme and `hostname`
    the host, the port is kept as given, and credentials, query and fragment are dropped.
    """
    parts = urlsplit(url)
    if parts.scheme not in ("http", "https") or not parts.hostname:
        raise ValueError(f"not an http(s) URL with a host: {url!r}")
    host = f"[{parts.hostname}]" if ":" in parts.hostname else parts.hostname
    # `.port` raises ValueError itself for a port that is not one.
    port = f":{parts.port}" if parts.port is not None else ""
    return f"{parts.scheme}://{host}{port}", parts.path


def normalised(pattern: str) -> str:
    """The one spelling a pattern is stored under: the origin, then the path with no trailing /."""
    origin, path = split(pattern)
    return origin + path.rstrip("/")


def matching(bindings: list[dict], url: str) -> list[dict]:
    """Every binding whose pattern covers `url`, best first.

    Same origin, and a prefix that is empty or ends on a whole path segment of the URL: `/docs`
    covers `/docs` and `/docs/a`, never `/docsx`. Best is the longest prefix, then the most
    recently used, and a binding never used goes last.
    """
    origin, path = split(url)
    found = []
    for binding in bindings:
        bound_origin, prefix = split(binding["pattern"])
        if bound_origin == origin and (not prefix or path == prefix
                                       or path.startswith(prefix + "/")):
            found.append((len(prefix), binding["last_used"] or "", binding))
    found.sort(key=lambda row: row[:2], reverse=True)
    return [binding for _, _, binding in found]
