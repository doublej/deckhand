"""The `deckhand` command's contract: every command, every failure code and its exit status.

Out of `cli.py`, which reached its line budget; `prime`, argparse and `docs/commands.md` are all
drawn from these tables, so they are data with no behaviour of their own.
"""

from __future__ import annotations

#: Exit status per category. 4 is not an error: it is a question answered "no" — not said, not
#: pushed, not answered yet — which a loop must be able to tell from a crash.
EXIT = {"user_error": 1, "upstream": 1, "internal": 1, "usage": 2, "transient": 3, "negative": 4}

#: code → (category, retryable, hint)
ERRORS: dict[str, tuple[str, bool, str]] = {
    "NO_SESSION": ("user_error", False, ("run it from a Claude Code session's Bash tool: it finds "
                   "its session by walking up to the `claude` process")),
    "DAEMON_DOWN": ("transient", True, ("start it: `launchctl kickstart -k "
                    "gui/$(id -u)/com.jurrejan.deckhand`, or `just daemon` in the deckhand repo")),
    "REFUSED": ("upstream", False, "the daemon's own words are in `message`"),
    "BAD_ANSWER": ("internal", True, "read the daemon's log: `just logs` in the deckhand repo"),
    "BAD_KIND": ("user_error", False, "--kind is one of confirm, pick, text, aloud"),
    "BAD_PLANE": ("user_error", False, ("a URL or --window ID, not both and not neither; "
                  "`deckhand windows` lists the ids")),
    "NO_SUCH_SESSION": ("user_error", False, ("`deckhand sessions` lists the names; a unique id "
                        "prefix or part of a name is enough")),
    "CODEX_THREAD": ("user_error", False, ("a Codex thread only takes the person's own words; "
                     "ask the person instead")),
    "NOT_DELIVERED": ("negative", False, ("it was not said — `message` says why; a filter on that "
                      "session may have stopped it")),
    "NOT_PUSHED": ("negative", False, ("the person has not seen it: this folder refuses "
                   "interruptions — say it in the conversation instead")),
    "PENDING": ("negative", True, ("no answer yet; the daemon messages this session when one "
                "lands, or block on it: `deckhand answer <id> --wait 300`")),
    "NO_SUCH_SLIP": ("user_error", False, ("no slip has that id in this session's folder: the id "
                     "is what `deckhand ask` printed")),
    "NO_SUCH_PLANE": ("user_error", False, ("`message` lists the planes open, by id prefix; "
                      "`deckhand space` shows them whole")),
    "NOT_STARTABLE": ("user_error", False, ("`message` says why and lists folders a session can "
                      "start in, nearest first; pass one to `deckhand start`")),
    "NO_TMUX": ("user_error", False, "no tmux server answers here: this session is not in tmux"),
    "NO_SUCH_TARGET": ("user_error", False, ("`deckhand tmux` lists every pane and window; a "
                       "session name, %pane, @window, session:index or window name")),
    "BAD_ARRANGE": ("user_error", False, ("rename and group need --name, move, swap and join "
                    "need --to, layout needs --layout")),
    "TMUX_REFUSED": ("upstream", False, "tmux's own words are in `message`"),
    "PERSON_ONLY": ("user_error", False, ("refused on purpose, not missing: it is the person's "
                    "own. Ask them — `deckhand presence` says where — rather than going around "
                    "it with curl")),
    "USAGE": ("usage", False, "`deckhand prime` lists every command and its arguments"),
}

#: The one command model: argparse and `prime` are both drawn from it. `tool` is the MCP tool the
#: command is, which is what keeps the two doors the same size.
COMMANDS: list[dict[str, str]] = [
    {"name": "presence", "tool": "presence", "args": "[--json]",
     "does": "where the person is: `laptop`, `headset` or `phone`, one word; --json adds idle seconds, "
             "screen lock and when the phone was last heard from"},
    {"name": "whoami", "tool": "whoami", "args": "", "does": "this session's id, name and folder"},
    {"name": "sessions", "tool": "sessions", "args": "[--fields name,status] [--limit 50]",
     "does": "every live session on this Mac, with how many slips each has waiting"},
    {"name": "ask", "tool": "ask_on_phone",
     "args": "QUESTION|- [--kind confirm|pick|text|aloud] [--option LABEL]... [--note TEXT] "
             "[--question id:text]... [--action TEXT] [--expires-hours H] [--key ID]",
     "does": "put a slip on the phone; answers with its id. confirm: two --option, yes then no, "
             "and --action. pick: one --option per choice. text: --option is the field label. "
             "aloud: --question per spoken answer. Then end the turn: a decision's answer arrives"},
    {"name": "answer", "tool": "read_answer", "args": "ID [--wait SECONDS]",
     "does": "the answer, `verified` if their phone signed it; exit 4 while none. --wait max 600"},
    {"name": "notify", "tool": "call_for_attention", "args": "LINE|-",
     "does": "a Lock Screen card asking for the person; exit 4 when the folder refuses"},
    {"name": "say", "tool": "say_to_session", "args": "SESSION TEXT|-",
     "does": "message another session down its inbox, as an agent — `manager` is the manager; "
             "exit 4 when it was not said"},
    {"name": "end", "tool": "ask_to_end", "args": "SESSION... --why TEXT",
     "does": "ask the person, on their phone, to end these sessions on any machine; ends "
             "nothing itself — only their Allow does"},
    {"name": "open", "tool": "open_plane", "args": "[URL] [--window ID] [--title TEXT]",
     "does": "put a web page, or a Mac window by id, beside this session in the person's "
             "headset; the URL must be reachable from the headset on the LAN"},
    {"name": "space", "tool": "space", "args": "[--full]",
     "does": "where this session is in the headset, what is beside it, and every page and window "
             "open; --full adds every kept pose"},
    {"name": "start", "tool": "start_session", "args": "[FOLDER] [--provider claude|codex|opencode]",
     "does": "start a session beside this one in the headset; brief it with `say`"},
    {"name": "close", "tool": "close_plane", "args": "ID|PREFIX",
     "does": "close a plane by its id or a unique prefix — a page or a window, never a session"},
    {"name": "windows", "tool": "mac_windows", "args": "",
     "does": "this Mac's windows, with the ids `open --window` takes"},
    {"name": "tmux", "tool": "tmux_tree", "args": "",
     "does": "every tmux session, window and pane, with the Claude session in each; `you` is "
             "this one's pane"},
    {"name": "arrange", "tool": "tmux_arrange",
     "args": "ACTION TARGET [--to TARGET] [--name TEXT] [--layout LAYOUT] [--split right|below]",
     "does": "move tmux's furniture: rename, group, ungroup, move, swap, join, break, layout, "
             "zoom, focus. TARGET is a session name, %pane, @window, session:index or window "
             "name"},
]

SESSION_FIELDS = ("session", "name", "folder", "status", "waiting", "provider")
