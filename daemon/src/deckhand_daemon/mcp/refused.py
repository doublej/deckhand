"""What an agent may not do, said where it would look for it, so it stops looking.

Each row is the person's own (`docs/agent-surface.md`): `route` is what does it for them, and no
tool or command reaches it. That is absence, not a fence — the token is a readable file and `curl`
still performs any of it — so the reason travels with the refusal, to be read rather than routed
around. One table, four places: the MCP server's instructions, `deckhand prime`, the
`PERSON_ONLY` answer `deckhand` gives any of these verbs, and `docs/commands.md`.
"""

from __future__ import annotations

REFUSED: list[dict[str, str]] = [
    {"verbs": "cancel stop compact clear exit kill", "route": "POST /sessions/{id}/control",
     "why": "keystrokes the person presses on a session's own pane. `clear` cannot be undone, "
            "and closing a session is theirs alone"},
    {"verbs": "rename", "route": "POST /sessions/{id}/name",
     "why": "it types `/rename` into the pane, which is the keyboard route and arrives as the "
            "person"},
    {"verbs": "type keyboard", "route": "POST /sessions/{id}/say?route=keyboard",
     "why": "the keyboard route arrives as the person at the machine; `say` goes down the "
            "socket labelled as an agent, and is the only way an agent speaks to a session"},
    {"verbs": "respond reply", "route": "POST /sessions/{id}/artifacts/{aid}/answer",
     "why": "a slip is answered by the person; an agent answering one is asking and answering "
            "itself"},
    {"verbs": "click input", "route": "POST /windows/{id}/input",
     "why": "it drives the Mac's real cursor and keyboard, which is the person's hand"},
    {"verbs": "settings filters orders", "route": "PUT /settings, PUT /sessions/{id}/filters, "
                                                  "PUT /sessions/{id}/orders",
     "why": "what this Mac and a session are set to do is the person's; an agent that can "
            "rewrite a filter chain can remove the filter that would have stopped it"},
    {"verbs": "pair devices forget", "route": "POST /pair/open, DELETE /devices/{id}",
     "why": "pairing hands a device everything this Mac's token can do, so it is opened by the "
            "person standing at the Mac (`just pair`), never on someone's behalf"},
    {"verbs": "send-keys kill-pane kill-window respawn",
     "route": "tmux send-keys, kill-pane, kill-window, respawn-pane",
     "why": "typing into a pane is the keyboard route, and killing or respawning one ends the "
            "session in it — the person's own press. `tmux_arrange` moves panes, never into them"},
    {"verbs": "manager", "route": "POST /manager/say",
     "why": "it speaks into the manager's conversation as the person. The manager is a session "
            "too: Claude Code's own SendMessage to `deckhand-manager` reaches it as an agent"},
]

#: verb → why, for the command line.
BY_VERB = {verb: f"{row['why']} ({row['route']})"
           for row in REFUSED for verb in row["verbs"].split()}


def markdown() -> str:
    """One line per row, for the server's instructions and `deckhand prime`."""
    return "\n".join(f"- {row['verbs'].replace(' ', ', ')} — `{row['route']}`: {row['why']}"
                     for row in REFUSED)
