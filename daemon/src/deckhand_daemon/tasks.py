"""The person's own list of asks for one session, and the only ways a model may change it.

The briefing is written from scratch every time, and for a while the list was too — so every run
produced a *new* list, and one that forgot what the last one said. A list that forgets is worse
than no list, because it looks like a record.

So the list lives in a file the Mac owns. The model is handed it, with ids, and gets three tools
and nothing else: add one, move one along, drop one. It cannot renumber, reword or re-order what
is already there, and it is not asked to trim: the history is kept here and the phone decides how
much of it to show. That division is the whole point — `MAX_KEPT` below is a ceiling on a file,
not a view.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

from .config import data_dir
from .log import log

# Not started, started, finished. The only judgement in the list.
STATES = ("todo", "doing", "done")
# One ask, in their words, shortened to a line. Longer than this is a paragraph, not a task.
MAX_TEXT = 120
# A ceiling on the file so a year-long session cannot grow one without bound. Nothing to do
# with how many the phone shows, which is the phone's business.
MAX_KEPT = 200


def path(session_id: str) -> Path:
    folder = data_dir() / "tasks"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f"{session_id}.json"


def load(session_id: str) -> list[dict]:
    """The list, oldest ask first. Empty when this session has never had one."""
    return _read(session_id)["tasks"]


def render(session_id: str) -> str:
    """The list as the model is shown it: the id it must use, the box, and the ask.

    Handing over the ids is what makes the tools usable, and handing over the list is what stops
    the model adding what is already in it.
    """
    lines = [
        f"  {task['id']} [{_box(task['state'])}] {task['text']}" for task in load(session_id)
    ]
    return "\n".join(lines) if lines else "  (empty)"


def add(session_id: str, text: str) -> dict:
    """Append an ask. An ask already in the list comes back unchanged rather than twice."""
    wanted = " ".join(text.split())[:MAX_TEXT]
    if not wanted:
        raise ValueError("a task needs some words")
    book = _read(session_id)
    for task in book["tasks"]:
        if _same(task["text"], wanted):
            return task
    task = {
        "id": f"t{book['next']}",
        "text": wanted,
        "state": "todo",
        "added": time.time(),
        "changed": time.time(),
    }
    book["next"] += 1
    book["tasks"].append(task)
    _trim(book)
    _write(session_id, book)
    return task


def set_state(session_id: str, task_id: str, state: str) -> dict | None:
    """Move one ask along. Returns the task, or None when there is no such id."""
    if state not in STATES:
        raise ValueError(f"no such state {state!r}")
    book = _read(session_id)
    for task in book["tasks"]:
        if task["id"] == task_id:
            task["state"], task["changed"] = state, time.time()
            _write(session_id, book)
            return task
    return None


def drop(session_id: str, task_id: str) -> dict | None:
    """Remove one ask for good. Returns what was removed, or None when there was no such id.

    This is the only operation that loses something, which is why the tool that calls it warns.
    An ask that was done is `done`; an ask the person withdrew is gone.
    """
    book = _read(session_id)
    for index, task in enumerate(book["tasks"]):
        if task["id"] == task_id:
            book["tasks"].pop(index)
            _write(session_id, book)
            log.warning("dropped task %s from %s: %s", task_id, session_id, task["text"])
            return task
    return None


def server(session_id: str):
    """The three tools, bound to one session's list. None of them can reach another session's.

    In-process, so a tool call is a function call: the list the phone reads a moment later is
    the same file this wrote, with no daemon round trip in between.
    """
    from claude_agent_sdk import create_sdk_mcp_server, tool

    @tool("add_task", "Add an ask the person has made that is not in the list yet. "
                      "Their words, shortened to a few. Never a step you decided to take.",
          {"text": str})
    async def add_task(args: dict) -> dict:
        task = add(session_id, args.get("text", ""))
        return _said(f"{task['id']} [{_box(task['state'])}] {task['text']}")

    @tool("set_task_state", "Move an ask along: todo (nothing done yet), doing (started, "
                            "unfinished), done (finished, nothing about it still open).",
          {"id": str, "state": str})
    async def set_task_state(args: dict) -> dict:
        task = set_state(session_id, args.get("id", ""), args.get("state", ""))
        if task is None:
            return _said(f"no task {args.get('id')!r} in this list — check the ids you were given")
        return _said(f"{task['id']} is now {task['state']}")

    @tool("drop_task", "Remove an ask for good. Only when the person withdrew it or it was "
                       "never theirs. An ask that is finished is done, not dropped.",
          {"id": str, "reason": str})
    async def drop_task(args: dict) -> dict:
        reason = " ".join(str(args.get("reason", "")).split())
        if not reason:
            return _said("drop_task needs a reason — say why this ask is not theirs any more")
        task = drop(session_id, args.get("id", ""))
        if task is None:
            return _said(f"no task {args.get('id')!r} in this list")
        return _said(f"dropped {task['id']} ({task['text']}). This list is a history and that "
                     f"entry is now gone from it — if it was finished rather than withdrawn, "
                     f"add it back and set it to done.")

    return create_sdk_mcp_server(name="tasks", tools=[add_task, set_task_state, drop_task])


# The names the model calls them by, once the server above is mounted.
TOOLS = ("mcp__tasks__add_task", "mcp__tasks__set_task_state", "mcp__tasks__drop_task")


def _said(text: str) -> dict:
    return {"content": [{"type": "text", "text": text}]}


def _box(state: str) -> str:
    return {"todo": " ", "doing": "~", "done": "x"}.get(state, " ")


def _same(one: str, other: str) -> bool:
    """Same ask, said twice. Case and punctuation are not part of what was asked."""
    return _plain(one) == _plain(other)


def _plain(text: str) -> str:
    return "".join(c for c in text.lower() if c.isalnum() or c.isspace()).strip()


def _read(session_id: str) -> dict:
    try:
        book = json.loads(path(session_id).read_text())
    except (OSError, json.JSONDecodeError):
        return {"next": 1, "tasks": []}
    if not isinstance(book, dict) or not isinstance(book.get("tasks"), list):
        return {"next": 1, "tasks": []}
    book.setdefault("next", len(book["tasks"]) + 1)
    return book


def _write(session_id: str, book: dict) -> None:
    path(session_id).write_text(json.dumps(book, indent=2))


def _trim(book: dict) -> None:
    """At the ceiling, the oldest finished ask goes. A list this long has stopped being read."""
    while len(book["tasks"]) > MAX_KEPT:
        oldest = next((t for t in book["tasks"] if t["state"] == "done"), book["tasks"][0])
        book["tasks"].remove(oldest)
