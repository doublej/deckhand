"""Everything that reads a Claude Code transcript, and nothing that writes one.

Three readings of the same JSONL, kept together because they share its shape and its hazards —
the lossy folder name, the megabyte tails, the entries that are Claude Code talking to itself.
`transcripts` is the conversation, `asked` is the person's side of it and the session's inbox,
`readable` is the whole file as lines. Anything that acts on what they find lives outside.
"""
