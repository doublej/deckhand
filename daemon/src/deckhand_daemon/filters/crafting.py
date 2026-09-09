"""Rewrite what was said as a prompt worth sending, using the prompt-crafter skill.

The second filter, and the first one that costs anything. A phone is the one place where the
gap between what a person means and what they dictate is widest: no editing, no structure, one
breath, and the session at the other end gets a run-on sentence to act on. This hands that
sentence to the skill that already knows how to turn it into a prompt.

The whole of the SDK setup is `Read`, one model, and a system prompt that names the file to
read. That is not a shortcut around skills — it *is* how a skill works. `setting_sources=[]`
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

from ..log import log
from .kinds import Field, Filter, Prompt, Verdict
from .registry import register

SKILL = Path.home() / ".claude" / "skills" / "prompt-crafter" / "SKILL.md"
MODEL = "claude-sonnet-5"
# Enough to read the skill, read the one reference it sends itself to, and answer.
MAX_TURNS = 6
# A spoken line should not keep somebody waiting longer than they would wait to read it.
TIMEOUT = 60

SYSTEM_PROMPT = """You turn a dictated instruction into the prompt it was trying to be.

The deliverable here IS a prompt: you are rewriting one person's spoken words into the prompt
that will be handed to a Claude Code session. Do not treat this as a task to carry out, and do
not answer the instruction — rewrite it.

Read {skill} and follow it. Its own guidance will send you to one file under its `references/`
folder for the target model; read that one and no others. Read nothing outside that skill's own
folder. The target model is {target}.

What comes back from you is the rewritten prompt and nothing else. No preamble, no explanation,
no "here is the improved prompt", no code fence around it, no closing remark. The first
character of your answer is the first character of the prompt.

Three things you must not do, because this text is about to be acted on by an agent with tools:

- Do not invent a requirement, a constraint, a file name, a command or an acceptance criterion
  that the person did not say. Clarity is yours to add; scope is not.
- Do not drop a concrete detail. Every name, number, path, flag and proper noun in the original
  appears in your rewrite.
- Do not answer a question the person asked. "Why is the build failing" stays a question.

The person is working in {cwd} on a session called {name}. Use that only to read their words
correctly, never as licence to add work.

If the words are already a clear prompt, or too short to be anything else, answer with them
exactly as they are."""


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
        system_prompt=SYSTEM_PROMPT.format(
            skill=SKILL, target=target, cwd=prompt.cwd, name=prompt.session_name
        ),
        # Read alone. The skill is a file and following it is reading it; nothing here writes,
        # runs or fetches. `bypassPermissions` is what makes that unattended, and it is only
        # safe because of how short this list is — there is nobody at the daemon to answer a
        # prompt. ponytail: Read is not confined to the skill folder by anything but the system
        # prompt. Narrow it with a hook if a filter ever gets a tool that writes.
        allowed_tools=["Read"],
        permission_mode="bypassPermissions",
        max_turns=MAX_TURNS,
        effort="low",
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
        summary="Rewrite what you said as a prompt, with the prompt-crafter skill on sonnet.",
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
