"""Rewrite what was said as a prompt worth sending, using the prompt-crafter skill.

The second filter, and the first one that costs anything. A phone is the one place where the
gap between what a person means and what they dictate is widest: no editing, no structure, one
breath, and the session at the other end gets a run-on sentence to act on. This hands that
sentence to the skill that already knows how to turn it into a prompt.

The whole of the SDK setup is `Read`, one model, and a system prompt that names the file to
read — all of it declared in `prompts/crafting.md`. That is not a shortcut around skills — it *is* how a skill works. `setting_sources=[]`
for the reason `summarize.py` records (loading the user's config starts every MCP server they
have configured, which cost more than a minute), and a skill is only reachable through the
settings it is declared in. So rather than pay that, the skill's own progressive disclosure is
used directly: the agent reads `SKILL.md`, and the skill tells it which single reference file it
needs for the target model. Two reads and an answer.

**This filter is not idempotent**, and it is the first one that is not. Crafting an already
crafted prompt rewrites it a second time. That is why `/say` grew a `prepared` flag: once a
person has read the words on the card, those are the words, and the chain does not run again.
"""

from __future__ import annotations

import asyncio
from pathlib import Path

from .. import prompts
from ..log import log
from .kinds import Field, Filter, Prompt, Verdict
from .registry import register

CRAFTING = prompts.load("crafting")
SKILL = Path(CRAFTING.settings["skill"]).expanduser()
MODEL = CRAFTING.settings["model"]
MAX_TURNS = CRAFTING.settings["max_turns"]
TIMEOUT = CRAFTING.settings["timeout"]
SYSTEM_PROMPT = CRAFTING.body


async def _craft(prompt: Prompt, settings: dict) -> Verdict:
    """Silent and unchanged on every failure: a filter must not be able to eat what was said."""
    if not SKILL.is_file():
        return Verdict(note=f"prompt-crafter is not installed at {SKILL}")
    if len(prompt.text.split()) < _floor(settings):
        return Verdict()
    crafted, trouble = await _run(prompt, str(settings.get("target") or "generic"))
    if trouble:
        log.warning("crafting for %s: %s", prompt.session_name, trouble)
        return Verdict(note=f"could not craft the prompt: {trouble}")
    if not crafted or crafted == prompt.text:
        return Verdict()
    return Verdict(text=crafted, note="rewritten as a prompt")


def _floor(settings: dict) -> int:
    """Below this many words there is nothing to craft, and a model run is pure cost.

    "yes", "carry on", "stop and explain" are the commonest things said to a session and the
    worst possible candidates for rewriting — there is no structure to add and every word of
    them is already the whole instruction.
    """
    given = settings.get("floor")
    return int(given) if isinstance(given, (int, float)) and given > 0 else 12


async def _run(prompt: Prompt, target: str) -> tuple[str | None, str | None]:
    """One model, one tool, no settings, no MCP. Every expected failure is a sentence."""
    try:
        from claude_agent_sdk import ClaudeAgentOptions, ClaudeSDKError, ResultMessage, query
    except ImportError:
        return None, "claude-agent-sdk is not installed"

    options = ClaudeAgentOptions(
        model=MODEL,
        system_prompt=CRAFTING.filled(
            skill=SKILL, target=target, cwd=prompt.cwd, name=prompt.session_name
        ),
        # Read alone. The skill is a file and following it is reading it; nothing here writes,
        # runs or fetches. `bypassPermissions` is what makes that unattended, and it is only
        # safe because of how short this list is — there is nobody at the daemon to answer a
        # prompt. ponytail: Read is not confined to the skill folder by anything but the system
        # prompt. Narrow it with a hook if a filter ever gets a tool that writes.
        allowed_tools=CRAFTING.settings["allowed_tools"],
        permission_mode="bypassPermissions",
        max_turns=MAX_TURNS,
        effort=CRAFTING.settings["effort"],
        setting_sources=[],
    )

    async def collect() -> tuple[str | None, str | None]:
        async for message in query(prompt=prompt.text, options=options):
            if isinstance(message, ResultMessage):
                if message.is_error:
                    return None, f"the model returned an error: {message.subtype}"
                return (message.result or "").strip() or None, None
        return None, "the model returned nothing"

    task = asyncio.create_task(collect())
    try:
        # Shielded for the reason summarize.py records: on a timeout the task is dropped rather
        # than waited on while the CLI unwinds, which is what left the phone hanging.
        return await asyncio.wait_for(asyncio.shield(task), timeout=TIMEOUT)
    except TimeoutError:
        task.cancel()
        return None, f"the model did not answer within {TIMEOUT}s"
    except (ClaudeSDKError, OSError) as error:
        return None, f"the model could not be reached: {error}"


CRAFT = register(
    Filter(
        name="craft",
        title="Prompt crafting",
        summary="Rewrite what you said as a prompt, with the prompt-crafter skill on opus.",
        fields=[
            Field(
                key="target",
                label="Written for",
                kind="text",
                default="opus-5",
                hint="The model that will read it: opus-5, sonnet-5, fable-5, or generic",
            ),
            Field(
                key="floor",
                label="Shortest worth crafting",
                kind="number",
                default=12,
                hint="Words. Below this the words are sent as they are, unchanged and for free",
            ),
        ],
        apply=_craft,
    )
)
