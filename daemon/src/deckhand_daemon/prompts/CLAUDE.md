# Prompts

## What this is

Every prompt this daemon sends a model, and nothing else. One markdown file per agent, in the
shape Claude Code writes an agent definition in: YAML frontmatter for the settings its run needs
— model, effort, turns, timeout, and the tool descriptions, each with the reason it is what it
is — and the body is the prompt verbatim.

```
__init__.py     # frontmatter and body, out of one markdown file
briefing.md     # the briefing agent: what it writes, its model, its three tools
crafting.md     # the prompt-crafting filter's agent
decision-answer.md # the person's signed answer to a decision, typed into the asker
idle-check.md   # what a session that has gone quiet is asked
manager.md      # the manager: its voice, its authority, its twelve tool descriptions
manager-away.md # put in front of what is said when the run is read off the Lock Screen
space-given.md  # told to a session the person put a page or window beside
space-taken.md  # told to a session the person took one away from: closed, handed on, moved off
```

## Invariants

- **A prompt is a file, not a Python string.** The modules keep their own `MODEL` and `TIMEOUT`,
  read from the file at import, so nothing downstream knows a file is involved — and an edit
  takes a daemon restart.
- **Placeholders are filled by plain replacement, never `str.format`.** The body is a file
  somebody edits, and a literal brace in a pasted JSON example would otherwise raise on every
  prompt built from it forever.
- **A missing or unclosed fence raises at import** rather than starting a daemon that writes no
  briefings.

## Related context

- `../../../../docs/prompt-review.md` — the standing audit and its rollout order
