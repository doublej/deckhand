"""What the person has set this Mac to do — everywhere, and per project where they differ.

Four things on this Mac act without being asked, and each is one switch:

- **finished** — a session stopped and is waiting on you.
- **slips** — a session put a slip on your phone and nothing has answered it.
- **called** — an agent asked for your attention outright, in its own words.
- **chase** — the idle check messages a session that went quiet owing work. Not a notification
  at all; it is the Mac speaking to a session rather than to you, which is exactly why it wants
  a switch of its own.

Everything is keyed by **path**. The global value is the default and a folder's own value
overrides it, per key — a project that only wants a different summariser keeps every other
answer without restating it, and goes on following the global switch when that switch changes.

Path rather than session id, and this is the one judgement call in here: a session id changes
every restart, so a preference filed under one would have to be set again every morning. The
folder is stable and it is what a person actually has an opinion about. A session's own page
edits the folder it is running in, so from the phone it still reads as "this session".

What is deliberately *not* here: a switch per push. `push.py` raises a card, drops one when the
session goes, and re-announces when you answer — the last two are that card's bookkeeping, and
turning one off would strand a card on the Lock Screen with nothing able to clear it.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, replace
from pathlib import Path

from ..config import data_dir
from ..log import log

#: What `claude --model` takes. Aliases rather than ids: the CLI resolves them to whatever is
#: current, which is the right answer for a flag a person set once and forgot about.
SESSION_MODELS = ("opus", "sonnet", "haiku")
#: What the summariser may run on. Full ids, because the Agent SDK takes an id and an alias here
#: would be a silent no-op. Empty means "whatever `prompts/briefing.md` says", which is the only
#: answer that keeps working when that file is edited.
SUMMARY_MODELS = ("claude-haiku-4-5-20251001", "claude-sonnet-5", "claude-opus-5")


@dataclass(slots=True, frozen=True)
class Wants:
    """The answers that apply somewhere — globally, or in one folder."""

    #: A session here stopped and is waiting on you.
    finished: bool = True
    #: A slip written here is waiting for an answer.
    slips: bool = True
    #: An agent here asked for you outright — `POST /sessions/{id}/notify`.
    called: bool = True
    #: Let the idle check ask a session here about the asks still open on its list.
    chase: bool = True
    #: Let the summariser read what this folder's subagents did, not only what the session said.
    #: Off by default: it is more transcript to read, and most sessions spawn nothing.
    subagents: bool = False
    #: What a session started in this folder runs on. Empty is Claude Code's own default.
    session_model: str = ""
    #: What writes the briefings for this folder. Empty is whatever the prompt file says.
    summary_model: str = ""

    def to_json(self) -> dict:
        return {
            "finished": self.finished,
            "slips": self.slips,
            "called": self.called,
            "chase": self.chase,
            "subagents": self.subagents,
            "session_model": self.session_model,
            "summary_model": self.summary_model,
        }


def path() -> Path:
    return data_dir() / "settings.json"


def document() -> dict:
    """The whole thing as stored: the global answers, plus a `projects` map of overrides.

    A file that is not there is not a problem — it means nothing has been changed yet, and the
    defaults on `Wants` are the answer. A file that is there and unreadable *is* worth saying
    out loud, because the person's choices are silently not being applied.
    """
    try:
        stored = json.loads(path().read_text())
    except FileNotFoundError:
        return _document(Wants(), {})
    except (OSError, json.JSONDecodeError) as error:
        log.warning("settings.json is there but unreadable, using the defaults: %s", error)
        return _document(Wants(), {})
    if not isinstance(stored, dict):
        return _document(Wants(), {})
    return _document(_wants(stored, Wants()), _overrides(stored.get("projects")))


def save(sent: object) -> dict:
    """Write what the phone sent, and hand back what was actually stored.

    Read back rather than echoed, because the two differ: an unknown key is dropped, a model
    this Mac does not offer is refused, and a project override that says nothing is removed
    rather than kept as an empty object. A screen that showed what it sent would be showing
    something that is not true of the Mac.
    """
    if not isinstance(sent, dict):
        return document()
    whole = _wants(sent, Wants())
    projects = {
        folder: over
        for folder, row in _overrides(sent.get("projects")).items()
        if (over := {k: v for k, v in row.items() if v is not None})
    }
    written = _document(whole, projects)
    try:
        path().write_text(json.dumps(written, indent=2) + "\n")
    except OSError as error:
        log.warning("could not write settings.json: %s", error)
    return written


def resolved(folder: str) -> Wants:
    """What applies in one folder: the global answers with that folder's own laid over them.

    Per key, not per object. A project that has only ever been given a different summariser
    still follows the global switch for everything else, and goes on following it when that
    switch is changed.
    """
    stored = document()
    whole = _wants(stored, Wants())
    over = stored.get("projects", {}).get(str(folder or ""))
    if not isinstance(over, dict):
        return whole
    return replace(whole, **{key: value for key, value in over.items() if value is not None})


def _document(whole: Wants, projects: dict[str, dict]) -> dict:
    return {**whole.to_json(), "projects": projects,
            "offers": {"session": list(SESSION_MODELS), "summary": list(SUMMARY_MODELS)}}


def _wants(row: dict, fallback: Wants) -> Wants:
    """One set of answers out of whatever was sent, keeping the fallback for anything absent."""
    return Wants(
        finished=_flag(row.get("finished"), fallback.finished),
        slips=_flag(row.get("slips"), fallback.slips),
        called=_flag(row.get("called"), fallback.called),
        chase=_flag(row.get("chase"), fallback.chase),
        subagents=_flag(row.get("subagents"), fallback.subagents),
        session_model=_model(row.get("session_model"), SESSION_MODELS) or fallback.session_model,
        summary_model=_model(row.get("summary_model"), SUMMARY_MODELS) or fallback.summary_model,
    )


def _overrides(sent: object) -> dict[str, dict]:
    """The per-project map, with only the keys a project actually overrode.

    `None` is what "follow the global answer" looks like on the wire, and it is kept as `None`
    here rather than resolved: this is the *document*, and the document has to be able to say
    that a project has no opinion. `resolved` is where an opinion becomes an answer.
    """
    if not isinstance(sent, dict):
        return {}
    found: dict[str, dict] = {}
    for folder, row in sent.items():
        if not isinstance(folder, str) or not folder or not isinstance(row, dict):
            continue
        found[folder] = {
            "finished": _flag(row.get("finished"), None),
            "slips": _flag(row.get("slips"), None),
            "called": _flag(row.get("called"), None),
            "chase": _flag(row.get("chase"), None),
            "subagents": _flag(row.get("subagents"), None),
            "session_model": _model(row.get("session_model"), SESSION_MODELS),
            "summary_model": _model(row.get("summary_model"), SUMMARY_MODELS),
        }
    return found


def _flag(value: object, fallback: bool | None) -> bool | None:
    return value if isinstance(value, bool) else fallback


def _model(value: object, offered: tuple[str, ...]) -> str | None:
    """A model this Mac offers, or nothing.

    Refused rather than passed through: an unknown string here becomes a `--model` flag on a real
    launch line or a model id the SDK will reject, and both fail somewhere far away from the
    screen that set it. The empty string is an answer — it means "the default" — and is kept.
    """
    if not isinstance(value, str):
        return None
    word = value.strip()
    if word == "":
        return ""
    return word if word in offered else None
