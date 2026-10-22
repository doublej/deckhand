# What a session gets told Deckhand can do

> A plan, not a build. The complaint it answers: an agent working inside a Deckhand-managed
> session has a phone in the person's pocket and no idea it can reach it.

Every capability in this repo is aimed at the person holding the phone. Almost none of it is
aimed at the agent that would use it. A session can write a slip, push a card to the Lock
Screen, read another session's state and draw a diagram in what it says — and does none of
those, because nothing ever tells it they exist.

## The honest answer

**A skill, and no MCP server yet.** The deciding fact is that Deckhand's most valuable
capability needs no tool at all. A slip is a file the agent writes in its own `cwd` with
`Write` and reads back with `Read`; that was the whole point of putting artifacts in the
project rather than in Application Support. An agent that does not know about slips is not
missing a tool, it is missing a paragraph.

Sorted by what is actually missing:

| Capability | What an agent lacks | Which side |
|---|---|---|
| Write a slip, read the answer | Knowing it exists, and the page's rules | Knowledge |
| Declare an aloud slip's questions | The shape of one JSON block | Knowledge |
| Prefill from `window.deckhand.answer` | Knowing it is expected of a page | Knowledge |
| A mermaid fence draws on the phone | Knowing the phone renders it | Knowledge |
| Say **slip** to a person, **artifact** in code | Vocabulary | Knowledge |
| `POST /notify` — ask for the person outright | The route, and that the folder may refuse | A call |
| Read the listing, or another session's state | The route and the token | A call |
| Speak into another session | The route, the receipt, and the authority rule | A call |

Seven-eighths of the surface is prose. The remaining three are HTTP calls an agent can make
with `curl` today, and their only subtlety is reading the receipt — which is also prose.

This is not the answer for every project. It is the answer for this one because Deckhand
deliberately chose a file lane over a tool lane once already, in `docs/artifacts.md`: "no new
tool, no MCP, no token, no discovery step — an agent knows its own cwd and nothing else is
needed." A skill is that decision carried forward. An MCP server would be that decision
reversed for the sake of tidiness.

The MCP server is designed below and phased last, with the fact that starts it named. It is
worth building when the skill demonstrably fails to fire, and not before.

## Three things an agent already has and does not know it has

**It knows its own session id.** `CLAUDE_CODE_SESSION_ID` is injected into every Bash tool
call and equals the `sessionId` in `~/.claude/sessions/<pid>.json` — the same key `/sessions/{id}`
takes. `CLAUDE_PID` is beside it. Verified this pass against pid 99607's record. Note it is not
in the `claude` process's own exec-time environment, only in the environment of the shells it
spawns, which is exactly where it is wanted. There is no discovery step and no daemon change
needed to get one: an agent that wants to talk about itself already can.

**It can read the token.** `~/Library/Application Support/Deckhand/token` is mode 600 owned by
the person, and the agent runs as that person. `-H "x-deckhand-token: $(cat …)"` keeps the
secret out of the transcript because the shell expands it after the command is recorded.

**The phone draws mermaid.** A ` ```mermaid ` fence in what a session *says* renders as a
picture in the transcript, the briefing and any report (0312c54, renderer bundled). It does
**not** render inside a slip — an artifact page is sandboxed by its own CSP and the renderer
is injected, not carried. The skill has to say both halves, because "diagrams work" plus a
slip that shows raw source is a worse outcome than never mentioning it.

## The skill

One skill, `deckhand`, installed personally rather than per project. Every session on this Mac
is a Deckhand session, so the folder it is running in has nothing to do with whether the phone
can be reached. Personal scope puts the description in context for all of them at about a
hundred tokens, which is the standing invitation the whole plan turns on.

Source of truth in this repo at `skills/deckhand/`, symlinked to `~/.claude/skills/deckhand`,
which is the pattern `launchd/com.jurrejan.deckhand.plist` already follows. One copy, one gate,
`just install-skill` beside `just install-agent`.

```yaml
---
name: deckhand
description: Ask the person a question on their phone and read the answer, or reach them when
  they are away from the Mac. Use when a decision needs the person and they are not at the
  keyboard, when a choice has more than two options, when a long job finishes with nobody
  watching, or when the session is stuck and waiting silently is the wrong thing to do.
license: MIT
metadata:
  version: "1.0"
---
```

`name` must match the directory, is capped at 64 characters and may not contain "claude" or
"anthropic"; `description` is capped at 1024. Those six fields are the whole portable
specification. Claude Code accepts a much larger superset — `paths`, `model`, `context: fork`
and a dozen others — and its own documentation warns that including them breaks packaging
anywhere else, so none is used. `allowed-tools` is left off deliberately: it is marked
experimental, and it narrows rather than widens, so the only thing it can do here is take
`Write` away from a skill whose main verb is writing a file.

The description is the part to labour over. It is the only thing always in context, and every
failure of this plan looks the same — a session that had a decision to make and made it alone.
So it names the four moments rather than the feature.

**The body, under a hundred and twenty lines.** When to write a slip rather than simply say
something; the three-line recipe; the aloud block quoted whole; the CSP in one sentence; the
rule that a reopened page prefills from `window.deckhand.answer`; and **slip** to a person,
**artifact** in code. It ends with pointers and nothing else — the guidance is to keep bundled
references one level deep, because a reference that points at a further reference gets read
with `head` and comes back half-true.

```
skills/deckhand/
  SKILL.md              # the four moments, the recipe, the aloud block, the words
  reference/wire.md     # every endpoint, its shape, and the trap in it
  reference/traps.md    # the invariants: the route, Delivery.went, clear, null
  templates/            # symlinks to ../../demos/*.html — one copy, gated by just demo-check
  scripts/slip.py       # write a slip from arguments instead of authoring HTML
  scripts/answer.py     # block until a slip is answered, print the value
```

`reference/wire.md` is not new work. `.orchestrate/capabilities.md` is already twenty-seven
verified endpoints with their traps, written last week and explicitly labelled "not a skill yet
— an index to build one from". It is also inside a gitignored folder, so it is one `rm -rf` from
gone. Promoting it into the skill is the whole of phase one's second half, and it saves the
index at the same time.

## The two scripts

A slip is cheap to answer and expensive to write: `demos/pick.html` is a hundred and nine lines,
and an agent asking a two-option question should not be emitting a hundred lines of HTML to do
it. Shipping an executable is the documented pattern for exactly this — a pre-made script is
more reliable than generated code and costs only its output in context.

`scripts/slip.py --kind pick --title "Which branch" --option develop --option main` writes the
page from the matching template and prints the path. `--kind aloud --question id:text` writes the
declaration block and lets the app draw the cards. `scripts/answer.py <slug> --wait 300` blocks
on the answer file and prints the value, so the common shape — ask, wait, carry on — is two
commands rather than a polling loop the agent invents each time.

Both are thin: they copy a template and substitute a title, a slug and a list. Neither talks to
the daemon, because neither needs to.

## The MCP server, and the fact that starts it

**Built on 2026-09-10, ahead of that evidence and on JJ's say-so** — the point of the surface was
always that a session could work the app rather than only read about it. It lives in
`daemon/src/deckhand_daemon/mcp/`, is installed once with `just install-mcp`, and is the sixteen
tools in [`docs/commands.md`](commands.md) with the refusals below. Two of them do not touch the daemon at all: `ask_on_phone`
and `read_answer` run the skill's own scripts, so the tool and the shell command write the same
file. The rest of this section is what was designed and is what shipped; phase 3's agent token
still does not exist, so every refusal here remains a default rather than a guarantee.

The evidence that was going to start it, kept because it is still the thing to measure: sessions that reached a
decision needing the person, had the skill's description in context, and decided alone anyway.
That is the only failure a tool fixes and prose does not, because a tool is present whether or
not the model thought to look.

Design it now so the decision is a build rather than a design. Six tools, which is inside the
budget where tool search is unnecessary — the current guidance is that under ten tools plain
tool calling is right, and that selection degrades past thirty to fifty.

| Tool | Arguments | Returns |
|---|---|---|
| `whoami` | — | this session's id, name, folder, whether it has a pane |
| `ask_on_phone` | `question`, `kind`, `options?`, `hint?`, `id?` | `{id, title, waiting: true}` |
| `read_answer` | `id`, `wait_seconds?` (capped at 600) | `{answered, value}` |
| `call_for_attention` | `line` | `{pushed}` or `{pushed: false, why}` |
| `sessions` | — | name, folder, state and waiting slips per live session |
| `say_to_session` | `session`, `text` | `{went, by, why?}` — socket route, always |

`whoami`, `read_answer` and `sessions` carry `readOnlyHint: true`. All six carry
`openWorldHint: false`: the Mac is a closed world and nothing here reaches past it. The
annotations are hints and the specification says clients should never make decisions on hints
from an untrusted server, so they are a courtesy to the client, not a control.

**Elicitation is the wrong primitive and looks like the right one.** As of the 2026-07-28
revision a server asks for input by returning `resultType: "input_required"` and having the
client retry the call. It is the only client feature not deprecated and it is genuinely well
built. But it draws its dialog wherever the *client* is, which is the terminal on the Mac — the
one screen the person is definitionally not at when any of this matters. Deckhand's whole
premise is that the question goes to the phone. A slip is Deckhand's elicitation, and it is the
better one here because it survives the person being asleep.

## Transport, packaging, and how a session gets it

**stdio**, and a console script in the daemon's own uv project rather than a second package.
The server needs `httpx` and the token path, both of which `deckhand_daemon` already has.
`[project.scripts] deckhand-mcp = "deckhand_daemon.mcp:main"`, then
`claude mcp add --scope user deckhand -- deckhand-mcp` once.

Not an `/mcp` route on the daemon, tempting as one process sounds. The daemon binds `0.0.0.0`
so the phone can reach it, and a streamable-HTTP MCP endpoint there is LAN-reachable — the spec
requires `Origin` validation and a local bind for exactly the DNS-rebinding reason, and the
daemon can satisfy neither without giving up the phone. It would also put a URL and a token in
a config file in every repo. Over stdio the specification says outright not to follow the
authorization spec and to take credentials from the environment instead, which is what a
process running as the person already has: it reads the token file itself, resolves its session
from `CLAUDE_CODE_SESSION_ID`, and no project holds any configuration at all.

**The daemon should not install anything.** It knows every live session's `cwd` and could write
`.claude/skills/deckhand/` into each one — Claude Code watches those directories and picks up a
new skill mid-session, provided the folder existed when the session started. It should not,
because nothing about this is per project. One personal skill covers all four hundred and
sixty-five folders; per-project installation makes four hundred and sixty-five copies of one
file to keep in step. The one gap worth knowing: personal skills do not load in cloud sessions,
so a session running somewhere other than this Mac gets nothing — which is correct, since it
cannot reach this Mac's daemon either.

A plugin is the packaging unit that would ship the skill and the server together, with the
server declared in a `.mcp.json` at the plugin root. It is the right answer the moment either
half has a second consumer. Today both halves have one Mac and one person, and a symlink plus
one `claude mcp add` is less machinery for the same result.

## How this relates to driving the app

`docs/control-surface.md` plans the opposite direction of travel. There, something outside the
phone reaches in and drives the app's own state — a router, a `Command`/`Reply` façade, the
twenty-two presentation gates. Here, a session already running on the Mac reaches out to the
person. Neither needs the other and neither blocks the other.

They meet at exactly two points, and both are that document's, not this one's. The first is
that a surface which can speak must not use the pairing token. The second is that neither may
manufacture the keyboard route. Design the second token once, for both.

## What it must refuse

The invariant is that the route is an authority choice. The keyboard route arrives as the
person at the machine; the peer socket arrives labelled as another Claude session carrying none
of the person's authority. An agent-facing surface is, by construction, the thing that wrapper
exists to constrain, so the refusals are the load-bearing part of this plan rather than a
postscript.

- **No route argument anywhere.** `say_to_session` is socket-only and takes no route. An agent
  choosing `keyboard` is an agent claiming to be the person, which is the one thing the whole
  design refuses. The same rule governs the skill's prose: it documents `route` as the person's
  setting and never as an agent's parameter. `say_to_session manager` reaches the manager down its
  inbox the same way; `/manager/say` would arrive as the person.
- **No `/control`.** Cancel, compact and clear are keystrokes the person presses. `clear` is the
  only irreversible thing in the app and must not be a verb here at all, exactly as
  `control-surface.md` concluded for its own surface.
- **No `PUT /settings` and no `PUT /filters`.** An agent that can rewrite a session's filter
  chain can remove the filter that would have stopped it. That is the laundering shape one level
  up from the socket, and it is worse because it is quiet.
- **No `POST /projects/session`.** Starting a session is starting a process on a launch line
  nobody approved, in a folder whose trust dialog was answered for a person, not for an agent.
  `start_session` is the one exception: `POST /space/sessions` starts one beside the caller,
  through the same listing and trust gates as the phone, and it stands in the caller's group.
- **No `/file` and no widening of `/sessions/{id}/files`.** The listing is the permission,
  re-derived per request. An agent has `Read` and does not need a second path to the disk.
- **`call_for_attention` inherits the folder's refusal** rather than routing around it. `called`
  is the one trigger a session raises for itself and therefore the one a folder may refuse
  outright; the refusal comes back as `{pushed: false, why}` and the agent is expected to say so.
- **Planes, yes; sessions, no.** `open_plane`/`close_plane` move furniture in the headset
  (`docs/space.md`). A session is never a kept plane, so nothing here closes one — that stays
  `/control exit`, the person's press. An agent may only *ask*: `request_end_session` names sessions on
  one Allow/Deny alert, and the person's signed Allow is the press (`push/end_requests.py`).
- **The refusals are one table**, `mcp/refused.py`, rendered into the server's instructions,
  `deckhand prime`, `docs/commands.md`, and a `PERSON_ONLY` answer per verb.

**None of these is a fence, and the plan should not pretend otherwise.** The agent keeps `Bash`,
the pairing token is a readable file, and anything a tool declines `curl` still performs. What
is being defended against is an agent *drifting* into speaking as the person because that route
was the convenient one — not an agent attacking the Mac it is already running on. Defending
against the second means the daemon has to be able to tell an agent from a phone, which today
it cannot: one shared token, and the phone and the session look identical to it.

That is the one daemon change worth proposing here. **An agent token, distinct from the pairing
token**, which the daemon refuses `route=keyboard`, `/control`, both `PUT`s and
`/projects/session` for. Then the refusals above are enforced where they can be enforced, the
tool surface merely agrees with them, and `control-surface.md`'s second token is the same token.
Until it exists, every refusal in this section is a default rather than a guarantee, and the
skill should say so where it documents them.

**One thing is now a fence: a decision's answer** ([`artifacts.md`](artifacts.md#decisions)). It
is proven by the phone's own key, filed once with a device token only a phone paired by code holds,
and the daemon refuses any decision answer that is not signed by it — so an agent holding the
shared token can no longer write, curl or `respond` its way to the person's approval. `answer.py`
and `read_answer` re-check the signature themselves, so a hand-written answer file reads
`verified: false`. This closes the forged-approval gap without the agent token.

**`x-deckhand-caller: agent` is a drift guard, not a fence.** `mcp/here.py` and the `deckhand`
command send it on every call; `/say` then adds no "JJ, spoken:", carries no standing orders and
leaves the card up, and `POST /presence/phone` answers 403. An agent with `Bash` can leave the
header off, exactly as it can `curl` past every other refusal here — the point is that the tools
an agent is given never dress its words as the person's.

## The bill

About two days, and the first half-day is worth more than the rest together.

| Phase | Size | What it buys |
|---|---|---|
| **1 — the skill** | half a day | `SKILL.md`, the two references, the symlink, `just install-skill`. Rescues `.orchestrate/capabilities.md` from a gitignored folder on the way. **Nearly all the value.** |
| 2 — the scripts | half a day | Asking costs one command instead of a hundred lines of HTML. |
| 3 — the agent token | half a day | Makes the refusals real rather than advisory. Shared with `control-surface.md`. |
| 4 — the MCP server | one day | Six tools over stdio. Conditional: build it when sessions are still deciding alone. |
| 5 — mermaid in a slip | small | The one thing the skill otherwise has to document as a "not yet". |

Stop after phase one and read a week of transcripts. If sessions start asking, phases three and
four can wait indefinitely; if they do not, the description is wrong and no tool will save it.

## Sources

Read against the current tree, not recalled: `daemon/src/deckhand_daemon/app.py`,
`artifacts.py`, `saying.py`, `sessions.py`, `daemon/CLAUDE.md`, `docs/artifacts.md`,
`docs/control-surface.md`, `GLOSSARY.md`, `demos/README.md`, `.orchestrate/capabilities.md`,
`.orchestrate/queue.md`. The session-id join and the `ps` visibility limit were measured on this
Mac on 2026-09-10.

Read online the same day, because none of it was safe to recall:

- MCP revision `2026-07-28` — <https://modelcontextprotocol.io/specification/2026-07-28/changelog>,
  and the transports and elicitation pages under the same revision. HTTP+SSE was deprecated in
  `2025-03-26` and is now formally scheduled for removal; elicitation became a returned
  `input_required` result plus a client retry, and roots, sampling and logging were deprecated.
- Tool annotations and their defaults — the `2026-07-28` `server/tools` page, which also states
  that clients should not make decisions on annotations from untrusted servers.
- stdio takes credentials from the environment and skips the authorization spec —
  <https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization>.
- Tool budgets — <https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool>
  (under ten tools, plain tool calling; selection degrades past thirty to fifty). Undated page.
- Skill frontmatter, the six portable fields and their limits —
  <https://agentskills.io/specification>, mirrored in `anthropics/skills` as
  `spec/agent-skills-spec.md`.
- Progressive disclosure, the five-hundred-line body ceiling and the one-level-deep rule for
  references — <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>.
- Skill discovery, precedence, the mid-session directory watcher, and the warning that Claude
  Code-only frontmatter breaks packaging elsewhere — <https://code.claude.com/docs/en/skills>.
- Skills against MCP, stated directly — <https://code.claude.com/docs/en/features-overview>:
  "MCP gives Claude purpose-built tools for an external system… Skills give Claude knowledge
  about how to use those tools effectively." The same page says idle MCP tools now cost little
  context, so the older "tool schemas are expensive up front" argument is no longer the reason
  to prefer a skill. The reason here is that the capability is a file, not a call.
- Plugins as the unit that ships a skill and a server together, with `.mcp.json` at the plugin
  root — <https://code.claude.com/docs/en/plugins-reference>.
