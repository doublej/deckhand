"""Opening a session: a project by name, any folder by path, or a new one in the sandbox.

Split off `doing.py` for the line cap, and the line falls in a sensible place: everything here
**makes** a session, and everything left there speaks to one that exists.

`start_session` is deliberately allowed where `docs/agent-surface.md` refuses it. That refusal is
about an agent starting a process nobody asked for, and this one only ever runs because somebody
spoke into the panel.

**It opens one anywhere on the network**, because `POST /projects/session` already did: the phone
has been able to start a session on Ubuntu or Fractal since the fleet landed, and the manager
could not, and so answered that there was no such machine.

**And it opens any folder, not only a catalogued one.** A name is looked up and keeps both gates
it always had; a path is taken exactly as typed and keeps neither. That is the one place in this
daemon where the listing is not the permission, it is deliberate, and `_begin_at` carries why.

`start_scratch_session` is the one thing here that makes a *folder*, and the bound is why it is
not a general "create a folder" verb: it is the sandbox or it is nothing.
`projects.starting.scratch_folder` holds the whole of where; read it before widening.
"""

from __future__ import annotations

import re
from pathlib import Path

from ..fleet import registry
from ..projects import routes as project_routes
from ..projects import sources, starting
from ..settings import wants
from . import talk
from .tools import said

#: What makes `start_session` read its argument as a folder rather than as a project name: a
#: POSIX path, a `~`, or a Windows drive — Fractal's folders are spelled `C:/dev/...`. Anything
#: else is a name and goes through the catalogue, gates and all.
A_PATH = re.compile(r"^(/|~|[A-Za-z]:[\\/])")


async def begin(wanted: str, machine: str, model: str = "") -> dict:
    """Start Claude Code in a folder: a project by name, or any folder by path.

    **A name is looked up and a path is taken**, and that one sentence is the whole of the
    difference. A name is resolved against atlas's catalogue and keeps both gates it always had.
    A path is the person pointing at a folder, so neither gate has anything left to say — see
    `_begin_at`.
    """
    if (model := _model(model)) is None:
        return said(f"the model is one of {', '.join(wants.SESSION_MODELS)}, or empty for the folder's own.")
    here = registry.here()
    wanted = (wanted or "").strip()
    if A_PATH.match(wanted):
        return await _begin_at(wanted, (machine or "").strip().lower() or here, here, model)
    matches = _matching(wanted, machine, here)
    if not matches:
        where = f" on {machine}" if machine else " on any machine"
        return said(f"no project called {wanted!r}{where}. Use list_projects to find it.")
    if len({m.machine or here for m in matches}) > 1:
        named = ", ".join(sorted({m.machine or here for m in matches}))
        return said(f"{wanted!r} is a folder on more than one machine ({named}). Say which one.")
    match = matches[0]
    on = match.machine or here
    if on != here:
        # The hand runs the same trust check against its own record and answers in a sentence,
        # so it is not repeated here against a disk that knows nothing about that folder.
        started, error = await project_routes.start_over_there(on, match.path, model)
        if started is None:
            talk.say("act", f"could not start a session in {match.name} on {on}: {error}")
            return said(f"it did not start on {on}: {error}")
        name = started.get("name", match.name)
        talk.say("act", f"started {name} in {match.relative or match.path} on {on}")
        return said(
            f"{name} is running in {match.path} on {on}. It has no pane, so it can only "
            f"be spoken to — which is what say_to_session does anyway."
        )
    if match.path not in starting.trusted():
        return said(
            f"{match.name} has never been trusted by Claude Code, so a session started there "
            f"would stop at a trust prompt nobody can answer. The person has to open it once "
            f"themselves."
        )
    session, error = starting.start(match.path, model=model)
    if session is None:
        talk.say("act", f"could not start a session in {match.name}: {error}")
        return said(f"it did not start: {error}")
    sources.forget()
    talk.say("act", f"started {session.name} in {match.relative or match.path}")
    return said(f"{session.name} is running in {match.path}.")


async def _begin_at(path: str, on: str, here: str, model: str = "") -> dict:
    """Start a session in a folder the person named outright, catalogued or not.

    **This is the one door where the listing is not the permission, and that is what it is for.**
    Everywhere else a folder has to be on atlas's list, which is what keeps `POST
    /projects/session` from being a way to run Claude Code anywhere on a disk — and the phone's
    picker still works exactly that way, unchanged. The manager's door is wider because JJ asked
    for one: the words arrive from the panel in their hand, and a path said out loud is a person
    choosing a folder in the most direct way there is. Nothing is inferred and nothing is
    searched for; what is typed is what is opened.

    The trust record yields **on this Mac only**, and that asymmetry is measured rather than
    chosen. Here, Claude Code asks nothing in an untrusted folder, so the record stands in for
    somebody having chosen it — which is the very thing that just happened. On Ubuntu the same
    launch line drew the dialog and sat on it, so a hand keeps its own check and says so; the
    refusal names the folder and the machine, and answering it there once is the whole fix.

    What does **not** yield anywhere: the folder has to exist, on the machine named, and a
    machine that is not this one has to answer. `~` is expanded on the machine it belongs to and
    never here.
    """
    if on not in {m.id for m in registry.machines()}:
        named = ", ".join(sorted(m.id for m in registry.machines()))
        return said(f"there is no machine called {on!r}. They are: {named}.")
    if on != here:
        started, error = await project_routes.start_over_there(on, path, model)
        if started is None:
            talk.say("act", f"could not start a session in {path} on {on}: {error}")
            return said(f"it did not start on {on}: {error}")
        name = started.get("name", Path(path).name)
        talk.say("act", f"started {name} in {path} on {on}")
        return said(
            f"{name} is running in {started.get('cwd', path)} on {on}. It has no pane, "
            f"so it can only be spoken to."
        )
    folder = Path(path).expanduser()
    if not folder.is_dir():
        return said(f"{path} is not a folder on this Mac, so nothing was opened.")
    session, error = starting.start(str(folder.resolve()), person_named_it=True, model=model)
    if session is None:
        talk.say("act", f"could not start a session in {folder}: {error}")
        return said(f"it did not start: {error}")
    talk.say("act", f"started {session.name} in {folder}")
    return said(f"{session.name} is running in {session.cwd}.")


def _matching(wanted: str, machine: str, here: str) -> list[sources.Project]:
    """Every catalogued folder that name could mean, an exact one winning over a path fragment.

    A list rather than the first hit, because the same project name exists on two machines here
    and picking one of them quietly is how a session lands on the wrong side of the network.
    """
    found, _ = sources.catalog()
    lowered = (wanted or "").strip().lower()
    machine = (machine or "").strip().lower()
    if machine:
        found = [p for p in found if (p.machine or here).lower() == machine]
    exact = [p for p in found if p.name.lower() == lowered or p.path.lower() == lowered]
    return exact or [p for p in found if lowered and lowered in p.relative.lower()]


def _model(model: str) -> str | None:
    """The model asked for one start, lowered; "" for the folder's own; None for no such model."""
    model = (model or "").strip().lower()
    return model if model in ("", *wants.SESSION_MODELS) else None


def scratch(task: str, model: str = "") -> dict:
    """Make a folder under the sandbox for a task with no home, and start a session in it."""
    if (model := _model(model)) is None:
        return said(f"the model is one of {', '.join(wants.SESSION_MODELS)}, or empty for the folder's own.")
    folder, why = starting.scratch_folder(task)
    if folder is None:
        return said(why)
    session, error = starting.start(str(folder), model=model)
    if session is None:
        talk.say("act", f"made {folder.name} but nothing started in it: {error}")
        return said(f"the folder is there and nothing started in it: {error}")
    sources.forget()
    talk.say("act", f"started {session.name} in a new scratch folder, {folder.name}")
    return said(
        f"{session.name} is running in {folder}, a folder made for this and holding nothing "
        f"else. Say what the work is with say_to_session — it has been told nothing yet."
    )
