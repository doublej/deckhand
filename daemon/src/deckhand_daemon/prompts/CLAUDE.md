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
idle-check.md   # what a session that has gone quiet is asked
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
