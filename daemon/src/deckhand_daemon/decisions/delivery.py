"""A verified answer goes back as the person, into the session that asked, and nowhere else.

**The keyboard, whatever the presence or the Settings route.** The phone's key proved the person
tapped it, so it arrives as the person typing — the socket would stamp it as another agent's and
demote exactly the approval this was built to carry. `person=True` puts "JJ, spoken:" on it only
where it still goes down a socket: a session on another machine, which is P2's to fix.

**By the exact session id, with no succession.** `saying.found_session` follows a `/clear` to the
conversation now in that pane, which is right for words and wrong for an approval: the session
that asked is gone, and the one that replaced it never asked anything. So when the lookup hands
back a different id, or none, nothing is typed and the answer stays on disk.

**Not into a permission prompt.** Words typed while a pane shows Claude Code's "Do you want to…"
dialog answer the dialog, not the session. The sweep tries again every pass until it lands or the
decision lapses.
"""

from __future__ import annotations

import json
from pathlib import Path

from .. import deliver, plugin, prompts, saying
from ..fleet import here
from ..log import log
from ..sessions import panes
from . import answering

LINE = prompts.load("decision-answer")
GONE = "the asker is gone"
BLOCKED = "the asker is blocked at a permission prompt"


def blocked(pane_id: str) -> bool:
    """Whether the pane is showing a permission prompt rather than its prompt box.

    ponytail: read off the screen — Claude Code's own "Do you want to …" with a numbered "1. Yes",
    and no prompt box drawn. A pane merely *showing* those words above a live box still types.
    Swap for a status field the day Claude Code's session record carries one.
    """
    screen = panes.screen(pane_id)
    return "Do you want to" in screen and "1. Yes" in screen and not panes.BOX.search(screen)


def label(metas: dict, value: object) -> str:
    """The answer in the words the person saw: a confirm's button, a reply, a pick, a text."""
    if isinstance(value, dict) and isinstance(value.get("reply"), str):
        return LINE.settings["reply"].replace("{text}", value["reply"])
    answer = value.get("answer") if isinstance(value, dict) else value
    choices = metas.get("choices") or []
    if isinstance(answer, bool) and metas.get("decision") == "confirm":
        named = choices if len(choices) >= 2 else ["Yes", "No"]
        said = named[0 if answer else 1]
    else:
        said = answer if isinstance(answer, str) else json.dumps(answer, ensure_ascii=False)
    note = value.get("feedbackText") if isinstance(value, dict) else None
    return said + (LINE.settings["note"].replace("{text}", note) if isinstance(note, str) else "")


def line(artifact_id: str, question: str, metas: dict, value: object) -> str:
    """`Decision <id> — "<question>": <label>. This covers exactly: <action>.`"""
    return LINE.filled(id=artifact_id, question=question, label=label(metas, value),
                       action=metas.get("action") or question)


def handed(session_id: str, artifact_id: str, question: str, metas: dict, record: dict,
           answer: Path) -> tuple[str | None, str | None]:
    """Type the answer into the asker. `(route taken, error)`, as `deliver.deliver` answers."""
    found = saying.found_session(session_id)
    if found is None or found.session_id != session_id:
        return None, GONE
    words = line(artifact_id, question, metas, record["value"])
    if found.provider == "claude" and found.machine in ("", here()):
        if found.pane and blocked(found.pane.iterm_session_id):
            return None, BLOCKED
        taken, error = deliver.deliver(found, words, "keyboard", person=True)
    else:
        # Another machine, Codex or OpenCode: today's path, unchanged until P2.
        taken, error = deliver.deliver(found, words, plugin.route(), person=True)
    if taken is not None:
        answering.mark_delivered(answer, record)
        log.info("decision %s answered into %s by %s", artifact_id, found.name, taken)
    return taken, error
