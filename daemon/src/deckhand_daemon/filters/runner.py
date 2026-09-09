"""Walk the chain. The only part of this that is not obvious is what happens when a step breaks.

A filter is a small thing someone wrote to fix a word their dictation keeps getting wrong, and
the text it is handed is something a person actually said out loud. So a filter that raises is
logged, noted and stepped over, and the words carry on unchanged: the alternative is a typo in a
replacement list swallowing a message, which is the failure this chain exists to prevent rather
than to cause. Only a `stop` may end a prompt's journey, and only with a reason.
"""

from __future__ import annotations

import inspect
from dataclasses import replace

from ..log import log
from . import config, registry
from .kinds import Filter, Outcome, Prompt, Verdict


async def run(prompt: Prompt) -> Outcome:
    """Every step that is on, in order, each one handed what the last one left.

    The chain belongs to the terminal, so which steps these are comes from the prompt's own
    `session_name`: a prompt with no name behind it filters through nothing, which is what an
    unknown terminal should do rather than inheriting somebody else's chain.
    """
    outcome = Outcome(text=prompt.text)
    for step in config.load(prompt.session_name):
        name = step["filter"]
        if not step["on"]:
            continue
        flt = registry.get(name)
        if flt is None or flt.apply is None:
            # The chain outlives the filters: a saved step can name one this Mac no longer has.
            log.warning("the chain names %r, which is not a filter here", name)
            outcome.notes.append(f"{name} is not a filter on this Mac")
            continue
        verdict = await _verdict(flt, replace(prompt, text=outcome.text), step["settings"])
        if verdict is None:
            outcome.notes.append(f"{name} failed and was skipped")
            continue
        if verdict.stop:
            outcome.stopped_by = name
            # A message that vanishes without a reason is the bug this chain exists to avoid, so
            # a filter that refused something and forgot to say why still gets one written for it.
            outcome.reason = verdict.note or f"{name} stopped it"
            break
        if verdict.text is not None:
            outcome.text = verdict.text
        if verdict.note:
            outcome.notes.append(verdict.note)
    return outcome


async def _verdict(flt: Filter, prompt: Prompt, settings: dict) -> Verdict | None:
    """One step's answer, or None when it gave nothing usable. Sync or async, awaited either way."""
    try:
        answer = flt.apply(prompt, flt.settings(settings))
        if inspect.isawaitable(answer):
            answer = await answer
    except Exception:  # noqa: BLE001 -- a filter is somebody's small script: it may raise anything
        log.exception("filter %s raised, carrying the words on unchanged", flt.name)
        return None
    if isinstance(answer, Verdict):
        return answer
    log.warning("filter %s answered with %r, which is not a verdict", flt.name, answer)
    return None
