"""Everything that changes an OpenCode session: words, commands, a stop, a compact, a name.

**Two lanes in, and the difference is authority, exactly as for Claude.** `prompt` is admitted as
the user's own input, so `auto` and `keyboard` take it, and so does a slash command the person
said. `synthetic` is admitted as input that is not the user's, and it carries Deckhand's own
wrapper (`prompts/opencode-peer.md`) saying so. That is the `socket` route here: the lane the
manager, the idle check and the space notes speak on, chosen by JJ on 2026-10-16 over refusing
them as Codex does. Verified the same day against a throwaway session: synthetic input resumes the
loop, and the model named the wrapper's sender and said it carried no user authority.

`auto` never turns into the agent lane here. For a Claude session it does while the person is at
the laptop, because two things typing into one pane interleave; nothing here types into anything,
so that hazard is not there to step around.

**OpenCode's prompt steers by default.** Words for a busy session join the running turn at its
next step boundary, the way the TUI's own input does, rather than waiting behind it.
"""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from typing import TYPE_CHECKING

from .. import prompts
from ..log import log
from ..reading.commands import Command
from . import opencode
from .opencode import OpenCodeError

if TYPE_CHECKING:
    from .live import Session

PEER = prompts.load("opencode-peer")
#: The line OpenCode's own conversation and the phone show for a message on the agent lane.
SHOWN = str(PEER.settings.get("description_shown") or "Deckhand")
#: The key a synthetic message keeps the words in, unwrapped, so a reader can show what was said.
SAID = "deckhand"


def deliver(session: Session, message: str, route: str) -> tuple[str | None, str | None]:
    """Words into a session. Returns (route taken, error) as `deliver.deliver` does; never raises."""
    if route == "socket":
        return _as_peer(session, message)
    if message.startswith("/"):
        return _command(session, message)
    try:
        opencode.request("POST", f"/api/session/{session.session_id}/prompt",
                         {"text": message})
    except OpenCodeError as error:
        return None, f"OpenCode would not take the words for {session.name}: {error}"
    taken = "opencode-steered" if session.status == "busy" else "opencode-direct"
    log.info("%s took %d chars as %s", session.name, len(message), taken)
    return taken, None


def _as_peer(session: Session, message: str) -> tuple[str | None, str | None]:
    """The agent lane: synthetic input, wrapped so the model knows it is not the user."""
    if message.startswith("/"):
        return None, (f"{message.split()[0]} is a slash command, and on the agent lane "
                      f"{session.name} would receive it as words")
    try:
        opencode.request("POST", f"/api/session/{session.session_id}/synthetic", {
            "text": PEER.filled(message=message), "description": SHOWN,
            "metadata": {SAID: message}, "resume": True})
    except OpenCodeError as error:
        return None, f"OpenCode would not take the words for {session.name}: {error}"
    log.info("%s took %d chars on the agent lane", session.name, len(message))
    return "opencode-peer", None


def _command(session: Session, message: str) -> tuple[str | None, str | None]:
    """`/name the rest` as OpenCode's own command, or as a skill handed to a prompt."""
    name, _, rest = message[1:].partition(" ")
    try:
        opencode.request("POST", f"/api/session/{session.session_id}/command",
                         {"name": name, "text": rest})
        log.info("%s ran /%s", session.name, name)
        return "opencode-command", None
    except OpenCodeError as error:
        if "not found" not in str(error).lower():
            return None, f"OpenCode would not run /{name} in {session.name}: {error}"
    skill = next((s for s in _skills(session.cwd) if name in (s.get("id"), s.get("name"))), None)
    if skill is None:
        return None, f"OpenCode has no command or skill called /{name} in {session.name}'s folder"
    try:
        opencode.request("POST", f"/api/session/{session.session_id}/prompt",
                {"text": rest or f"Use the {skill.get('name')} skill.",
                 "skills": [{"id": skill["id"]}]})
    except OpenCodeError as error:
        return None, f"OpenCode would not hand {session.name} the {name} skill: {error}"
    log.info("%s was handed the %s skill", session.name, name)
    return "opencode-skill", None


def _skills(cwd: str) -> list[dict]:
    answer = opencode.request("GET", "/api/skill", query=opencode.located(cwd))
    return [s for s in answer.get("data") or [] if isinstance(s, dict) and s.get("id")]


def commands(session: Session) -> list[Command]:
    """OpenCode's commands and skills for this folder, as the phone's picker lists Claude's."""
    listed = opencode.request("GET", "/api/command", query=opencode.located(session.cwd))
    found = [Command(name=str(c["name"]), description=str(c.get("description") or ""), hint="",
                     kind="command", scope="project")
             for c in listed.get("data") or [] if isinstance(c, dict) and c.get("name")]
    named = {c.name for c in found}
    for skill in _skills(session.cwd):
        name = str(skill.get("name") or skill["id"])
        if name in named:
            continue
        inside = str(skill.get("path") or "").startswith(session.cwd.rstrip("/") + "/")
        found.append(Command(name=name, description=str(skill.get("description") or ""), hint="",
                             kind="skill", scope="project" if inside else "user"))
    return sorted(found, key=lambda c: (c.scope != "project", c.name.lower()))


def control(session: Session, action: str) -> str | None:
    """Stop and compact are OpenCode's own verbs. Clear and exit have no OpenCode equivalent."""
    try:
        if action == "cancel":
            if not _interrupt(session.session_id):
                return f"{session.name} has nothing running to stop"
        elif action == "compact":
            opencode.request("POST", f"/api/session/{session.session_id}/compact", {})
        else:
            return (f"{session.name} is an OpenCode session: it stops and compacts, and "
                    f"{action} is Claude Code's own command")
    except OpenCodeError as error:
        return f"OpenCode would not {action} {session.name}: {error}"
    log.info("sent %s to %s", action, session.name)
    return None


def _interrupt(session_id: str) -> bool:
    """Stop the session and every subagent running under it; whether anything was running.

    `resume=true`, because without it the words the person said into the turn stay parked and
    the session goes idle: they were never read, and the next prompt released them beside
    itself, so the person's line arrived twice. With it the session goes on to those words, as
    steering means. A subagent left running is a stop that did not stop, so each is stopped too.
    """
    running = set(opencode.request("GET", "/api/session/active").get("data") or {})
    under = [sid for sid in running if sid != session_id and opencode.root_of(sid) == session_id]
    stopped = opencode.request("POST", f"/api/session/{session_id}/interrupt",
                               query={"resume": "true"}).get("interrupted")
    for child in under:
        stopped = opencode.request("POST", f"/api/session/{child}/interrupt").get(
            "interrupted") or stopped
    return bool(stopped)


def rename(session: Session, name: str) -> str | None:
    """A session's title is its name, and OpenCode changes it at once — busy or not."""
    try:
        opencode.request("PATCH", f"/api/session/{session.session_id}", {"title": name})
    except OpenCodeError as error:
        return f"OpenCode would not rename {session.name}: {error}"
    log.info("renamed %s to %s", session.name, name)
    return None


def queued(session_id: str) -> list[dict]:
    """What is admitted and not yet delivered, oldest first, as the phone's queued rows."""
    return [{"text": text} for _, text in _inbox(session_id)]


def clear_queue(session_id: str) -> dict:
    """Cancel every prompt still waiting. OpenCode's own verb: a cancelled item is never read."""
    gone = 0
    for inbox_id, _ in _inbox(session_id, everything=True):
        opencode.request("DELETE", f"/api/session/{session_id}/inbox/{inbox_id}")
        gone += 1
    return {"cleared": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
            "cancelled": gone}


def _inbox(session_id: str, everything: bool = False) -> list[tuple[str, str]]:
    """(inbox id, words) for each prompt still waiting: the person's, or one Deckhand sent.

    OpenCode parks notes of its own here too — a shell "cancelled because the server restarted"
    sat in two idle sessions for hours — and those are not anybody's words waiting to be read.
    Clearing takes `everything`: a stale note left there rides into the model with the next prompt.
    """
    found = []
    for item in opencode.request("GET", f"/api/session/{session_id}/inbox").get("data") or []:
        if not isinstance(item, dict) or item.get("type") not in ("user", "synthetic"):
            continue
        payload = item.get("payload") or {}
        ours = item.get("type") == "synthetic" and SAID in (payload.get("metadata") or {})
        if not (item.get("type") == "user" or ours or everything):
            continue
        said = (payload.get("metadata") or {}).get(SAID) or payload.get("text") or ""
        found.append((str(item.get("id") or ""), str(said)))
    return found


def asks(session: Session) -> list[str]:
    """What this session is blocked on the person for: permission requests and forms, one line
    each. Only a running session can be waiting on one, so an idle one costs nothing."""
    if session.status != "busy":
        return []
    try:
        where = f"/api/session/{session.session_id}"
        asked = opencode.request("GET", f"{where}/permission").get("data") or []
        forms = opencode.request("GET", f"{where}/form").get("data") or []
    except OpenCodeError:
        return []
    lines = [_permission(p) for p in asked if isinstance(p, dict)]
    lines += [f"asks: {f.get('title') or 'a question'}" for f in forms if isinstance(f, dict)]
    return lines


def _permission(asked: dict) -> str:
    resources = [_short(str(r)) for r in asked.get("resources") or []]
    what = f"{asked.get('action', 'act')} {', '.join(resources[:2])}".strip()
    return f"wants permission to {what}" + (f" (+{len(resources) - 2})" if len(resources) > 2 else "")


def _short(resource: str) -> str:
    """A path as its last two parts; anything else, as long as a line allows."""
    parts = Path(resource).parts
    return "/".join(parts[-2:]) if resource.startswith("/") and len(parts) > 2 else resource[:80]
