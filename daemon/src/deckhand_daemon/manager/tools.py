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

import time
from pathlib import Path

from .. import artifacts, briefings, sessions, tasks
from ..filters import config as filter_config
from ..fleet import merge, proxy, registry
from ..orders import kept
from ..projects import routes as project_routes
from ..projects import sources
from ..reading import context, transcripts
from ..sessions import codex, codex_turns, opencode, opencode_turns
from ..settings import wants
from . import talk


def said(text: str) -> dict:
    """One tool answer. The shape the SDK takes, and the only place it is spelled out."""
    return {"content": [{"type": "text", "text": text}]}


def everywhere() -> list[sessions.Session]:
    """Every session on every machine, this Mac's first.

    The remote half comes out of the last listing rather than a fresh fan-out, which is what
    `merge` is for — and `listing()` is the tool the manager is told to call first, so by the
    time a name is being resolved the cache is a second old. A machine that has gone quiet since
    simply stops appearing, which is the right answer rather than a stale row.
    """
    local = sessions.live_sessions()
    remote = [built for row in merge.remote_rows() if (built := merge.session(row["session_id"]))]
    return local + remote


def find(wanted: str) -> sessions.Session | None:
    """The session that name or id means, or None. Exact name first, then id, then a prefix.

    This Mac wins a tie, because two machines genuinely can hold a session of the same name and
    the one in front of the person is the one they mean. Naming the machine is `list_sessions`'s
    job and the prompt says to look first.
    """
    live = everywhere()
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
    here = registry.here()
    names = (
        ", ".join(
            s.name if (s.machine or here) == here else f"{s.name} (on {s.machine})"
            for s in everywhere()
        )
        or "none — no session is running anywhere"
    )
    return {**said(f"no live session called {wanted!r}. Live right now: {names}"), "is_error": True}


def _quiet_for(updated_at: float) -> str:
    """How long since this session last did anything, coarse enough to read at a glance."""
    minutes = int(max(0, time.time() - updated_at) // 60)
    if minutes < 1:
        return "just now"
    if minutes < 60:
        return f"{minutes}m"
    return f"{minutes // 60}h"


async def listing(machine: str = "", state: str = "") -> dict:
    """Every machine, then every live session on all of them. The manager's first look, always.

    The machines come first and they are not decoration: without them a manager asked for
    something "on Ubuntu" has no way to know Ubuntu is a machine at all, and answers that it
    only manages this Mac — which was true of the tools and was never true of the network.

    This is also what fills `merge`'s map of which session is where, so every `find` after it
    can resolve a name on another machine.
    """
    local = sessions.live_sessions()
    rows = await merge.listings([s.to_json() for s in local])
    known = {s.session_id: s for s in local}
    here = registry.here()
    rows = [row for row in rows if (not machine or (row.get("machine") or here) == machine)
            and (not state or row.get("status") == state)]
    window = sessions.context_window()
    drawn = [
        _here_line(found, window)
        if (found := known.get(row.get("session_id", "")))
        else _away_line(row, here)
        for row in rows
    ]
    if machine or state:  # narrowed: the asker already knows the machines
        where = f" on {machine}" if machine else ""
        return said("\n".join(drawn) or f"no {state or 'live'} session{where} right now.")
    body = "\n".join(drawn) or "nothing is running on any machine right now."
    return said(f"{_machines(await merge.machines())}\n\n{body}")


def _machines(rows: list[dict]) -> str:
    """Which machines there are, by the names the person says, and which answer right now."""
    lines = [
        f"- {row['id']} ({row['label']}) — "
        + (
            "this Mac"
            if row.get("primary")
            else ("reachable" if row.get("reachable") else "not reachable right now")
        )
        + f", {row['os']}"
        for row in rows
    ]
    return "machines on this network:\n" + "\n".join(lines)


def _here_line(session: sessions.Session, window: int) -> str:
    """A session on this Mac: everything the daemon holds about it, on one line."""
    share, model = _fill(session, window)
    slips = artifacts.counted(session).get("artifacts_waiting", 0)
    open_asks = len(tasks.outstanding(session.session_id))
    headline = briefings.of(session.session_id).get("headline") or ""
    quiet = f" · quiet {_quiet_for(session.updated_at)}" if session.status != "busy" else ""
    return (
        f"- {session.name} [{session.status}] in {_tilde(session.cwd)} · context {share}"
        f" · {model}"
        f" · {open_asks} open ask(s) · {slips} slip(s) waiting"
        f" · {_reached(session)}{quiet}"
        + (f"\n    {headline}" if headline else "")
    )


def _fill(session: sessions.Session, window: int) -> tuple[str, str]:
    """How full its context is, and the model answering it: what decides reuse or a fresh start."""
    filled = sessions.filled(session, window)
    fill = filled["context"]
    share = f"{100 * fill['used'] // fill['limit']}%" if fill["limit"] and fill["used"] else "—"
    return share, (filled.get("model") or "model unknown").removeprefix("claude-")


def _away_line(row: dict, here: str) -> str:
    """A session on another machine, out of that machine's own listing.

    Fewer facts than a local row, and that is honest rather than lazy: how full a context is,
    what slips are waiting and what the last briefing said are read off the disk that holds the
    files, and this is the listing rather than the reading. `read_session` goes and asks.
    """
    status = row.get("status", "unknown")
    quiet = "" if status == "busy" else f" · quiet {_quiet_for(row.get('updated_at') or 0.0)}"
    return (
        f"- {row.get('name')} [{status}] on {row.get('machine') or here}"
        f" in {row.get('cwd')} · no pane{quiet}"
    )


async def one(session: sessions.Session, turns: int, before: int = 0, parts: str = "") -> dict:
    """Everything about one session worth knowing before acting on it.

    **Half of this is the daemon's and half is the session's own disk**, and the split decides
    which machine answers. The briefing, the ask list, the standing orders and the filter chain
    are kept here for every session wherever it runs, so they are read here. The slips and the
    transcript are files in the session's `cwd`, so for a session on another machine they are
    asked of that machine — reading this Mac's disk for them would answer about the wrong
    folder while looking exactly like an answer.
    """
    brief = briefings.of(session.session_id)
    chain = filter_config.load(filter_config.key(session.machine, session.name))
    here = registry.here()
    away = (session.machine or here) != here
    # `parts` names the sections wanted; empty is all of them. The head always comes.
    wanted = {name.strip() for name in parts.split(",") if name.strip()}
    sections = {
        "briefing": lambda: f"briefing: {brief.get('summary') or '(none written yet)'}",
        "asks": lambda: f"asks:\n{tasks.render(session.session_id)}",
        "orders": lambda: f"orders: {kept.load(session.session_id) or '(none)'}",
        "filters": lambda: f"filters: {_chain(chain)}",
    }
    drawn = [
        f"{session.name} [{session.status}] in {_tilde(session.cwd)}"
        + (f" on {session.machine}" if away else ""),
        f"id: {session.session_id}",
        *([] if away else ["context {} · {}".format(*_fill(session, sessions.context_window()))]),
        *(make() for name, make in sections.items() if not wanted or name in wanted),
    ]
    if not wanted or "slips" in wanted:
        rows = (
            (await _asked(session, "/artifacts")).get("artifacts", [])
            if away
            else artifacts.listing(session)
        )
        if waiting := [r for r in rows if not r.get("answered") and r.get("kind", "ask") == "ask"]:
            drawn.append("slips waiting: " + ", ".join(f"{r['id']} — {r['title']}" for r in waiting))
    if turns:
        drawn.append("conversation:\n" + await _turns(session, turns, away, before))
    return said("\n\n".join(drawn))


async def _asked(session: sessions.Session, path: str) -> dict:
    """One read handed to the machine that holds the files. Empty when it is not reachable,
    which every caller draws as "nothing to show" beside facts this daemon answered itself."""
    answer = await proxy.call(session.machine, "GET", f"/sessions/{session.session_id}{path}")
    return answer or {}


async def catalogue(query: str, machine: str, limit: int) -> dict:
    """Folders a session could be started in, on any machine, newest activity first.

    Filtered here rather than handed over whole: the network knows about several hundred and a
    listing that long is a tool answer nobody reads to the end of, model or person.

    **The folders themselves are read here**, out of atlas's catalogue, so a machine that is
    asleep still has its folders listed. Only the trust flag needs that machine: it is a dialog
    answered at its own keyboard and nothing else holds the answer. So a machine that did not
    answer has its folders marked *unknown* rather than untrusted — `/projects` draws the phone's
    picker the stricter way on purpose, but a sentence saying a folder cannot be started in is a
    fact, and "I could not ask" is not that fact.
    """
    found, source = sources.catalog()
    here = registry.here()
    query = (query or "").strip().lower()
    machine = (machine or "").strip().lower()
    if machine:
        found = [p for p in found if (p.machine or here).lower() == machine]
    if query:
        found = [p for p in found if query in p.name.lower() or query in p.relative.lower()]
    if not found:
        where = f" on {machine}" if machine else ""
        return said(f"no project matches {query!r}{where} (list from {source}).")
    allowed = await project_routes.trusted_everywhere(here)
    live = {(s.machine or here, s.cwd) for s in everywhere()}
    lines = [
        f"- {p.name} — {p.relative or p.path}"
        + (f" · on {p.machine}" if (p.machine or here) != here else "")
        + (f" · {p.framework}" if p.framework else "")
        + (f" · {p.branch}{'*' if p.dirty else ''}" if p.branch else "")
        + (" · a session is already here" if (p.machine or here, p.path) in live else "")
        + _trust(p, allowed, here)
        for p in found[:limit]
    ]
    more = f"\n({len(found) - limit} more; narrow the query)" if len(found) > limit else ""
    return said("\n".join(lines) + more)


def _trust(project: sources.Project, allowed: dict[str, frozenset[str]], here: str) -> str:
    """Whether Claude Code has been trusted there — or that nobody could be asked.

    A machine missing from `allowed` altogether did not answer, and its folders are unknown
    rather than refused. Said apart because the manager repeats this to a person, and "a session
    cannot be started here" is a different sentence from "that machine is asleep".
    """
    on = project.machine or here
    if on not in allowed:
        return f" · {on} did not answer — whether it is trusted there is unknown"
    if project.path in allowed[on]:
        return ""
    return " · NOT TRUSTED — a session cannot be started here"


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


async def loaded(session: sessions.Session, whole: bool = False) -> dict:
    """Every CLAUDE.md a session in that folder is running under, and what it costs.

    Asked of the machine the folder is on, for the reason `one` gives: a tree walked here for a
    path that only exists over there is a confident answer about a folder nobody asked about.
    """
    here = registry.here()
    if (session.machine or here) != here:
        answer = await _asked(session, "/context")
        found = answer.get("documents", [])
        docs = [(d.get("prefix", ""), d.get("label", ""), d.get("tokens", 0)) for d in found]
        total = answer.get("tokens", 0)
    else:
        read = context.documents(session.cwd)
        docs = [(d.prefix, d.label, d.tokens) for d in read]
        total = sum(d.tokens for d in read)
    if not docs:
        return said(f"{session.name} runs under no CLAUDE.md at all.")
    if not whole:  # the total and where it comes from; the tree is a thousand tokens on its own
        top = ", ".join(f"{label} ~{count}" for _, label, count in sorted(docs, key=lambda d: -d[2])[:5])
        return said(f"{session.name} is loaded with ~{total} tokens of context from {len(docs)} "
                    f"CLAUDE.md file(s); the largest: {top}. `whole` draws the tree.")
    lines = "\n".join(f"  {prefix}{label} — ~{count} tokens" for prefix, label, count in docs)
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


def _reached(session: sessions.Session) -> str:
    """How words get in. A Codex or OpenCode session never has a pane — its server's API is the
    way in — so "no pane" there would read as broken when it is only different."""
    if session.provider != "claude":
        return f"no pane, spoken to over {session.provider}'s API"
    return "pane" if session.pane else "no pane"


#: How much of one turn a reading shows. The rest is said to exist, never dropped in silence.
CUT = 400


async def _turns(session: sessions.Session, limit: int, away: bool, before: int = 0) -> str:
    """`limit` turns ending `before` from the newest: asked of the machine that holds them, else
    read where that provider keeps them — Claude's transcript, or the Codex or OpenCode server the
    phone's routes read. Says when a turn was cut and what `before` reads the page older."""
    if away:
        answer = await _asked(session, f"/turns?limit={limit}&before={before}")
        rows, more = answer.get("turns", []), bool(answer.get("more"))
        read = [(str(row.get("role", "")), str(row.get("text", ""))) for row in rows]
    else:
        reader = {"codex": codex_turns, opencode.PROVIDER: opencode_turns}.get(session.provider,
                                                                            transcripts)
        try:
            found, more = reader.page_turns(session.session_id, limit, before)
        except (codex.CodexError, opencode.OpenCodeError) as error:
            return f"  ({session.provider} would not answer: {error})"
        read = [(turn.role, turn.text) for turn in found]
    if not read:
        return "  (nothing readable in the transcript)"
    flat = [(role, " ".join(text.split())) for role, text in read]
    lines = [f"  {role}: {text[:CUT]}{'…' if len(text) > CUT else ''}" for role, text in flat]
    if any(len(text) > CUT for _, text in flat):
        lines.append(f"  (… is a turn cut at {CUT} characters: `look` /turns has them whole)")
    if more:
        lines.append(f"  (older turns: before={before + len(read)})")
    return "\n".join(lines)


def _tilde(folder: str) -> str:
    home = str(Path.home())
    return f"~{folder[len(home):]}" if folder.startswith(home) else folder
