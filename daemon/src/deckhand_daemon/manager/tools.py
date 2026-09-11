"""What the manager may read, and how a session is named to it.

Every tool here answers in plain lines rather than JSON. The manager is not parsing a wire, it
is reading — and a page of quoted braces costs more tokens and reads worse than the same facts
laid out. The one rule kept from the wire is that nothing is invented: a fact absent from the
Mac is absent from the answer rather than rendered as an empty string.

**A session is named, not addressed.** The person speaking to this panel says "deckhand", never
a UUID, so `find` takes either and prefers an exact name. A name that matches nothing comes back
as a sentence naming what *is* live, because a model told only "not found" will guess a second
UUID, and one told the actual list will not.
"""

from __future__ import annotations

from pathlib import Path

from .. import artifacts, briefings, sessions, tasks
from ..filters import config as filter_config
from ..orders import kept
from ..projects import sources, starting
from ..reading import context, transcripts
from ..settings import wants
from . import talk


def said(text: str) -> dict:
    """One tool answer. The shape the SDK takes, and the only place it is spelled out."""
    return {"content": [{"type": "text", "text": text}]}


def find(wanted: str) -> sessions.Session | None:
    """The session that name or id means, or None. Exact name first, then id, then a prefix."""
    live = sessions.live_sessions()
    wanted = (wanted or "").strip()
    for session in live:
        if session.name == wanted or session.session_id == wanted:
            return session
    lowered = wanted.lower()
    for session in live:
        if session.name.lower() == lowered:
            return session
    matched = [s for s in live if s.name.lower().startswith(lowered) and lowered]
    return matched[0] if len(matched) == 1 else None


def missing(wanted: str) -> dict:
    """What to say when a name matched nothing: the names that exist, so the next guess lands."""
    names = ", ".join(s.name for s in sessions.live_sessions()) or "none — no session is running"
    return said(f"no live session called {wanted!r}. Live right now: {names}")


def listing() -> dict:
    """Every live session in a line each. The manager's first look at the Mac, always."""
    live = sessions.live_sessions()
    if not live:
        return said("nothing is running on this Mac right now.")
    window = sessions.context_window()
    lines = []
    for session in live:
        request = sessions.last_request(session.session_id)
        share = f"{100 * request.used // window}%" if window and request.used else "—"
        slips = artifacts.counted(session).get("artifacts_waiting", 0)
        open_asks = len(tasks.outstanding(session.session_id))
        headline = briefings.of(session.session_id).get("headline") or ""
        lines.append(
            f"- {session.name} [{session.status}] in {_tilde(session.cwd)} · context {share}"
            f" · {open_asks} open ask(s) · {slips} slip(s) waiting"
            f" · {'pane' if session.pane else 'no pane'}"
            + (f"\n    {headline}" if headline else "")
        )
    return said("\n".join(lines))


def one(session: sessions.Session, turns: int) -> dict:
    """Everything about one session worth knowing before acting on it."""
    brief = briefings.of(session.session_id)
    chain = filter_config.load(filter_config.key(session.machine, session.name))
    parts = [
        f"{session.name} [{session.status}] in {_tilde(session.cwd)}",
        f"id: {session.session_id}",
        f"briefing: {brief.get('summary') or '(none written yet)'}",
        f"asks:\n{tasks.render(session.session_id)}",
        f"orders: {kept.load(session.session_id) or '(none)'}",
        f"filters: {_chain(chain)}",
    ]
    waiting = [row for row in artifacts.listing(session) if not row.get("answered")]
    if waiting:
        parts.append("slips waiting: " + ", ".join(f"{r['id']} — {r['title']}" for r in waiting))
    if turns:
        parts.append("last of the conversation:\n" + _turns(session.session_id, turns))
    return said("\n\n".join(parts))


def catalogue(query: str, limit: int) -> dict:
    """Folders a session could be started in, newest activity first.

    Filtered here rather than handed over whole: this Mac knows about several hundred and a
    listing that long is a tool answer nobody reads to the end of, model or person.
    """
    found, source = sources.catalog()
    query = (query or "").strip().lower()
    if query:
        found = [p for p in found if query in p.name.lower() or query in p.relative.lower()]
    trusted = starting.trusted()
    live = {Path(s.cwd) for s in sessions.live_sessions()}
    if not found:
        return said(f"no project matches {query!r} (list from {source}).")
    lines = [
        f"- {p.name} — {p.relative or p.path}"
        + (f" · {p.framework}" if p.framework else "")
        + (f" · {p.branch}{'*' if p.dirty else ''}" if p.branch else "")
        + (" · a session is already here" if Path(p.path) in live else "")
        + ("" if p.path in trusted else " · NOT TRUSTED — a session cannot be started here")
        for p in found[:limit]
    ]
    more = f"\n({len(found) - limit} more; narrow the query)" if len(found) > limit else ""
    return said("\n".join(lines) + more)


def switches(folder: str) -> dict:
    """What this Mac has been set to do — globally, or resolved for one folder."""
    if folder:
        answer = wants.resolved(folder).to_json()
        head = f"resolved for {_tilde(folder)}"
    else:
        answer = {k: v for k, v in wants.document().items() if k not in ("projects", "offers")}
        head = "globally"
    lines = "\n".join(f"  {key}: {value}" for key, value in answer.items())
    return said(f"{head}:\n{lines}")


def loaded(session: sessions.Session) -> dict:
    """Every CLAUDE.md a session in that folder is running under, and what it costs."""
    docs = context.documents(session.cwd)
    if not docs:
        return said(f"{session.name} runs under no CLAUDE.md at all.")
    total = sum(doc.tokens for doc in docs)
    lines = "\n".join(f"  {doc.prefix}{doc.label} — ~{doc.tokens} tokens" for doc in docs)
    return said(f"{session.name} is loaded with ~{total} tokens of context:\n{lines}")


def history(limit: int) -> dict:
    """What has already been said in this panel. For a manager picking up a cold conversation."""
    kept_entries = talk.entries()[-limit:]
    if not kept_entries:
        return said("this panel has no history yet.")
    return said("\n".join(f"{e['role']}: {e['text']}" for e in kept_entries))


def _chain(steps: list[dict]) -> str:
    """The chain in run order, with anything switched off said rather than left out."""
    drawn = [f"{s['filter']}{'' if s['on'] else ' (off)'}" for s in steps]
    return ", ".join(drawn) or "(none)"


def _turns(session_id: str, limit: int) -> str:
    read = transcripts.read_turns(session_id, limit=limit)
    if not read:
        return "  (nothing readable in the transcript)"
    return "\n".join(f"  {turn.role}: {' '.join(turn.text.split())[:400]}" for turn in read)


def _tilde(folder: str) -> str:
    home = str(Path.home())
    return f"~{folder[len(home):]}" if folder.startswith(home) else folder
