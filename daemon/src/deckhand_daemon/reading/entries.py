"""One transcript entry, read: its words, and who wrote them.

Split out of `transcripts` because this is the half that knows about *envelopes*. A message
reaches a session inside one — another session's, a teammate's, the harness's own notice that a
background agent has stopped — and two different questions are asked of that envelope: what did
it carry, and who sent it. `transcripts` assembles turns out of the answers and never opens one
itself.

Who sent it is not decoration. All of these arrive as a `user` entry, so a reader that goes by
`type` alone shows a subagent's report as words the person typed.
"""

from __future__ import annotations

import re

from . import machinery

MAX_TEXT = 4000
# Not everything that reaches a session is a person. Claude Code queues its own notices — a
# finished background task, a reminder — and those are machinery, not something anybody said.
MACHINE = re.compile(r"^\s*<\s*(?:task-notification|system-reminder|local-command-\w+)\b", re.IGNORECASE)


def blocks_of(entry: dict, sidechain: bool = False) -> str | None:
    """Every text block of one entry, joined, still inside whatever envelope carried it.

    Split out from `text_of` because who wrote a message is only legible before the envelope
    comes off — `machinery.wrote` reads the same string this returns.

    Tool calls, tool results, thinking blocks and subagent traffic are not part of the
    conversation the phone shows.

    **`sidechain` is which file is being read, not which entry.** Every row of a subagent's own
    transcript carries `isSidechain: true`, so dropping them is exactly right while reading the
    session's transcript — its agents' chatter is not its conversation — and exactly wrong while
    reading the agent's, where it is the only thing there is. Without the distinction a subagent
    reads as forty rows of nothing, which is what it did: three real agents, every one of them
    with `turns=0`.
    """
    if (entry.get("isSidechain") and not sidechain) or entry.get("isMeta"):
        return None
    message = entry.get("message")
    if not isinstance(message, dict):
        return None
    content = message.get("content")
    if isinstance(content, str):
        parts = [content]
    elif isinstance(content, list):
        if any(b.get("type") == "tool_result" for b in content if isinstance(b, dict)):
            return None
        parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
    else:
        return None
    return "\n".join(p for p in parts if p) or None


def text_of(entry: dict, sidechain: bool = False) -> str | None:
    """The human-readable text of one transcript entry, or None if it carries none."""
    raw = blocks_of(entry, sidechain)
    if raw is None:
        return None
    text = machinery.unwrapped(raw)
    # The keyboard route types ctrl-U before the words to clear whatever was half-written in the
    # prompt, and that control character is part of the entry Claude Code writes down.
    text = "".join(c for c in text if c.isprintable() or c.isspace()).strip()
    return text[:MAX_TEXT] if text else None


def unwrap(text: str) -> str:
    """The words themselves, out of whatever envelope carried them to the session.

    Deckhand's own socket route labels what it delivers, and a message from another session
    arrives inside a tag. Neither is what the person said, and neither belongs on the phone.

    Which tags come off is `machinery`'s list rather than "anything shaped like a tag": this
    once swept every `<...>` out of a queued message, and a prompt saying `Array<String>` lost
    the half of itself that mattered.
    """
    body = machinery.unwrapped(text)
    # Control characters and all: the keyboard route types ctrl-U before the words to clear
    # whatever was half-written in the prompt, and that ctrl-U travels with the message.
    body = "".join(c for c in body if c.isprintable() or c.isspace()).strip()
    _, marker, spoken = body.partition("transcribed:")
    return " ".join((spoken if marker else body).split())[:MAX_TEXT]


def queued(entry: dict) -> str | None:
    """Something said to a session that was already working, out of the entry that records it.

    A message that arrives mid-run never becomes a `user` entry — it is handed straight to the
    running turn and written down as a `queued_command` attachment instead. So it *is* in the
    transcript, at the moment it arrived, under a type nothing here was reading. Missing that is
    what made those messages look lost: the phone kept its own copy and showed it at the end of
    the conversation, where three answered prompts read as three that had gone unread.
    """
    if entry.get("type") != "attachment":
        return None
    attachment = entry.get("attachment")
    if not isinstance(attachment, dict) or attachment.get("type") != "queued_command":
        return None
    prompt = attachment.get("prompt")
    # Two shapes, and only one of them was being read. A typed message is a plain string; one
    # that carries a picture is a list of content blocks instead, with `imagePasteIds` beside
    # it. So a message with a screenshot attached vanished from the phone while the same words
    # typed alone came through — which reads as the app losing what you said, not as a shape it
    # could not parse.
    if isinstance(prompt, list):
        prompt = "\n".join(
            block.get("text", "") for block in prompt
            if isinstance(block, dict) and block.get("type") == "text"
        )
    if not isinstance(prompt, str) or not prompt or MACHINE.match(prompt):
        return None
    return prompt


def absorbed(entry: dict) -> str | None:
    """The same thing, with its envelope off — the words to put on the phone."""
    raw = queued(entry)
    return (unwrap(raw) or None) if raw is not None else None


def wrote_of(entry: dict) -> str:
    """Who wrote this entry, when it was not the person. Empty is the person themselves.

    Both shapes an arrival takes, because a subagent's notice and another session's message land
    as an ordinary `user` entry when the session was idle and as a `queued_command` attachment
    when it was mid-run — and the phone has to say the same thing about them either way.
    """
    if entry.get("isCompactSummary"):
        return "the compaction"  # Claude Code's summary of what came before, not the person
    return machinery.wrote(queued(entry) or blocks_of(entry) or "")
