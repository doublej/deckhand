"""Everything that reads what Claude Code has on this Mac, and nothing that writes any of it.

Three readings of one session's JSONL, kept together because they share its shape and its
hazards — the lossy folder name, the megabyte tails, the entries that are Claude Code talking to
itself. `transcripts` is the conversation, `asked` is the person's side of it and the session's
inbox, `readable` is the whole file as lines.

`commands` reads a different part of the same installation — the slash commands and skills a
session can be handed by name — and is here for the half of the rule that matters: it only ever
reads. Anything that acts on what any of them find lives outside this package.
"""
