"""The wrappers a message travels in, and how much of one is worth keeping.

What reaches a session is rarely only what somebody wrote. The harness puts tags around it —
another session's envelope, a reminder nobody typed, the caveat in front of a slash command's
output — and none of that is markup anything downstream renders, so it lands on the phone as
the literal characters it is.

Two answers, and which one a wrapper gets turns on whether it is hiding anything. A
`<system-reminder>` is machinery about machinery and goes whole. A `<teammate-message>` is
another session's entire report with a label on the front, and its `summary=` attribute was
written for a person to read — so the tag becomes that label and the body stays. Deleting one
of those would lose a message; keeping the other would keep a message nobody sent.

The list of names is the whole safety argument. An unknown tag is content until proven
otherwise — `<T>` in a Swift generic, `a < b`, an HTML snippet two sessions are discussing —
so this works off tags it knows by name and leaves everything else exactly where it was.
"""

from __future__ import annotations

import json
import re

# Machinery about machinery: nothing in here was written by a person, and the tag is not a
# label for anything worth reading.
NOISE = (
    "system-reminder",
    "local-command-caveat",
    "local-command-stdout",
    "command-name",
    "command-message",
    "command-args",
)
# One session's whole message to another. The envelope goes; what it carried does not.
PEER = ("teammate-message", "cross-session-message")

# Anything inside a fence or a backticked span is quoted, whatever it says. This repo's own
# transcripts are full of sessions showing each other these exact tags, and the conversation
# that asked for this rendering quotes every one of them at once. An unterminated fence takes
# the rest of the message with it on purpose: somebody opened a code block and never closed
# it, which is a reason to touch nothing after it rather than a reason to guess.
#
# Two levels rather than one, and the split between them is not tidiness. A fence is sacred to
# everything here. A backticked span is sacred only to the tag stripping, because the wrappers
# themselves routinely *contain* one — a peer's report is markdown and says `just check` in it —
# and one pattern covering both cuts those wrappers in half before anything can read them.
_FENCE = re.compile(r"(```.*?```|```.*)", re.DOTALL)
_INLINE = re.compile(r"(``.*?``|`[^`\n]+`)")

_NAMES = "|".join(NOISE)
_PEERS = "|".join(PEER)
# Attribute-tolerant, because the tags that carry a label are exactly the ones that carry
# attributes: a pattern for a bare `<teammate-message>` matches none of them in the wild.
_NOISY = re.compile(rf"<({_NAMES})\b[^>]*>.*?</\1\s*>", re.DOTALL | re.IGNORECASE)
_PEER_BLOCK = re.compile(rf"<({_PEERS})\b([^>]*)>(.*?)</\1\s*>", re.DOTALL | re.IGNORECASE)
_PEER_OPEN = re.compile(rf"<(?:{_PEERS})\b([^>]*)>", re.IGNORECASE)
_TASK = re.compile(
    r"<task-notification\b[^>]*>(.*?)</task-notification\s*>", re.DOTALL | re.IGNORECASE
)
# Whatever half of a known pair is left over — an unclosed noise tag, a stray closing tag part
# way down a message, either half of a wrapper whose body held a backtick. The tag goes and the
# words around it stay, which is the only answer to half a wrapper that cannot lose anything.
_ORPHAN = re.compile(rf"</?(?:{_NAMES}|{_PEERS}|task-notification)\b[^>]*>", re.IGNORECASE)

_ATTR = re.compile(r"([\w:-]+)\s*=\s*\"([^\"]*)\"")
# The two paragraphs the harness writes around a peer message. Both are the same words every
# time and both are addressed to the session rather than to the person reading it; the label
# put in their place says the one thing they carried that was not boilerplate — who wrote it.
_PREAMBLE = re.compile(r"^[^\S\n]*Another Claude session sent a message:[^\S\n]*\n", re.MULTILINE)
_CAVEAT = re.compile(r"This came from another Claude session[\s\S]*?(?=\n[^\S\n]*\n|\Z)")
# A session that has finished reports itself as a frame rather than in words, and the `result`
# in it is the whole of what it had to say. One line, alone on it: that is how the frame is
# written, and it is also what keeps this from reaching into a sentence that mentions one.
_IDLE = re.compile(
    r"^[^\S\n]*(\{\s*\"type\"\s*:\s*\"idle_notification\"[^\n]*\})[^\S\n]*$", re.MULTILINE
)
_GAPS = re.compile(r"\n{3,}")


def unwrapped(text: str) -> str:
    """The message with its machinery opened: noise gone, a peer's envelope turned into a label.

    Fences are handed back untouched — `re.split` on a capturing pattern puts them at the odd
    indices, so the quoted half of the text is never even looked at. Whether a peer envelope was
    seen is asked of the unquoted half only, so a message *showing* somebody one of these tags
    keeps every paragraph around it.
    """
    parts = _FENCE.split(text)
    plain = range(0, len(parts), 2)
    peered = any(_PEER_OPEN.search(parts[index]) for index in plain)
    for index in plain:
        parts[index] = _open(parts[index], peered)
    return "".join(parts).strip()


def _open(text: str, peered: bool) -> str:
    """One run of text with no fence in it."""
    body = _IDLE.sub(_idle, _TASK.sub(_task, text))
    body = _PEER_OPEN.sub(lambda match: _label(match.group(1)), _PEER_BLOCK.sub(_peer, body))
    if peered:
        body = _CAVEAT.sub("", _PREAMBLE.sub("", body))
    return _GAPS.sub("\n\n", _tags(body))


def _tags(text: str) -> str:
    """The wrapper tags themselves, with every backticked span left exactly as it was."""
    parts = _INLINE.split(text)
    for index in range(0, len(parts), 2):
        parts[index] = _ORPHAN.sub("", _NOISY.sub("", parts[index]))
    return "".join(parts)


def _peer(match: re.Match[str]) -> str:
    return _label(match.group(2)) + match.group(3).strip()


def _label(attrs: str) -> str:
    """Who wrote this, and what they said it was about — or nothing, when the tag says neither.

    A `from="uds:/tmp/cc-socks/99607.sock"` is not a name anybody wants at the top of a message,
    so an envelope carrying only that keeps the answer it has always had: the tag comes off and
    the words are left to stand on their own.
    """
    found = dict(_ATTR.findall(attrs))
    who = (found.get("teammate_id") or found.get("from-name") or "").strip()
    summary = found.get("summary", "").strip()
    if not who and not summary:
        return ""
    head = f"From {who}" if who else "From another session"
    return f"**{head}:** {summary}\n\n" if summary else f"**{head}**\n\n"


def _idle(match: re.Match[str]) -> str:
    try:
        return str(json.loads(match.group(1)).get("result") or match.group(0))
    except json.JSONDecodeError:
        return match.group(0)


def _task(match: re.Match[str]) -> str:
    """A finished background task, as the two parts of it a person would read.

    The ids, the output path and the status are for the session that asked for the run. The
    summary names what finished and the result is what it found, and dropping either would
    make a notice that answered a question look like a notice about nothing.
    """
    inner = match.group(1)
    summary = _child(inner, "summary") or "A background task finished"
    result = _child(inner, "result")
    return f"**{summary}**\n\n{result}" if result else f"**{summary}**"


def _child(inner: str, name: str) -> str:
    found = re.search(rf"<{name}\b[^>]*>([\s\S]*?)</{name}\s*>", inner, re.IGNORECASE)
    return found.group(1).strip() if found else ""
