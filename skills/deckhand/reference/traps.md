# Traps

The invariants that cost somebody time to learn and are invisible in the code. Verified against
the daemon's source on 2026-09-10.

## Asking

- **A page that has been answered must not draw itself empty.** `window.deckhand.answer` holds
  what the person last responded with, in exactly the shape it was responded with, or `null`. It
  is in place before the page's first line runs. Read it once while you are building the
  controls and prefill from it — tick the option that was picked, fill the fields that were
  filled. The row that opened the page says "answered"; a blank form under that is the page
  lying. Deckhand never inspects the shape and never normalises it, so treat an unexpected one
  as nothing answered.
- **`respond` may be called more than once.** The Mac just rewrites the answer file, so the
  person can change their mind and half a form now with the rest later is legitimate.
- **A slip only exists if its folder does, and nothing ever looks upward.** `.deckhand/artifacts/`
  is resolved from the session's own `cwd` and no enclosing directory is searched. A session
  started in `/` or in `$HOME` has no slips at all, silently. Writing one from a subdirectory
  puts it somewhere the phone will never list.
- **A slip is the session's own unless it is written flat.** `.deckhand/artifacts/<session
  id>/<slug>.html` is listed only by that session and answered back into it; `<slug>.html` flat in
  `.deckhand/artifacts/` belongs to the folder, is listed by every session working there, and is
  answered into whichever one the phone had open. `$CLAUDE_CODE_SESSION_ID` is the id, and both
  scripts use it without being told. A session id in a path is held to the same slug rule an
  artifact id is, so a session whose id fails it sees only the folder's slips.
- **The id is one strict slug**: `[A-Za-z0-9][A-Za-z0-9_-]{0,63}`. No dots, so `..` cannot be
  spelled; no separators, so no path can. Anything else is not an id and the page is not served.
  The same slug in both scopes is two different pages, and the session's own wins.
- **The `<title>` is the slip's name**, read out of the first 8 KB of the file. A `<title>`
  further in than that is not in the head, and the slip falls back to being named by its id.
- **An answer can never be JSON `null`.** FastAPI cannot tell an omitted field from an explicit
  null, so `null` is refused as a value. `false`, `0`, `""` and `[]` are all real answers and
  arrive intact — which is why a script waiting on one has to distinguish "no file yet" from
  "the answer was `false`".
- **The answer file is written before the session is messaged.** A delivery that fails never
  loses an answer; it is on disk either way.
- **Rewriting a page does not clear its answer.** The old `.answer.json` sits beside the new
  question and the phone draws the slip as answered. Delete it — that is also how you re-ask.
- **A page over 4 MB is refused**, so a `data:` picture has a ceiling.

## Talking at a page

- **Dictation into a field fires `input`, never `change`.** The app appends the words to whatever
  the field already holds and dispatches a real bubbling `input` event. A page gating on
  `keydown` watches a field fill up and never notices; `change` is deliberately not sent, because
  the person may say more or type.
- **A remark on a selection is not an answer.** While something is selected the hold-to-talk mark
  appears, and what the person says lands on the review card with the passage quoted above it,
  on its way into the session's inbox. It never goes through `respond`, and the page neither sees
  it nor can stop it.
- **A page that tears off the app's listeners loses itself the controls.** The injected script
  watches `selectionchange`, `focusin` and `focusout` and reports only *whether* there is a
  selection or a focused field — never the text.
- **`type="password"` is offered no dictation at all.**

## Speaking into a session

- **`delivered: true` is not the same as "it was said".** A filter can stop a prompt the daemon
  accepted, and the daemon still answers `delivered: true` alongside the stop. Ask
  `delivered && stopped_by == null`. The Swift client calls this `Delivery.went`, and nothing
  should ever check `delivered` alone.
- **A filter that raises is logged, noted as skipped, and the words carry on unchanged.** Only an
  explicit stop verdict, with a reason, halts a chain.
- **The keyboard route never silently falls back to the socket.** Choosing it is choosing whose
  authority the words carry, so with no pane it fails and says why. This is the invariant every
  refusal in `wire.md` hangs off.
- **A slash command only works typed into a pane.** Down the socket it is a *message*: the
  session reads words beginning with a slash, runs nothing, and reports no failure, because from
  where it sits nothing failed. The daemon refuses a leading `/` on the socket route and where
  there is no pane, which is the only way anyone finds out.
- **The socket wraps every message as "not from your user, carrying none of your user's
  authority."** That is a genuine control against one agent laundering permissions through
  another. It is not something to work around; it is the wrong channel for a person speaking.
- **There is no way to make a session read its inbox early.** The queue drains when a turn ends,
  so a message sent to a busy session is not a turn and appears nowhere in its transcript until
  it is absorbed. `queued` on `/turns` is the only honest answer to "has it seen this yet".
- **`clear` is the only irreversible action in the app**, and `exit` is the only one whose cost is
  the session itself. Neither is yours to send.

## Mermaid, both halves

A ` ```mermaid ` fence in what a session **says** renders as a picture on the phone — in the
transcript, in the briefing, in any report. The renderer is bundled with the app.

It does **not** render inside a slip. An artifact page is sandboxed by a CSP the app injects
(`default-src 'none'`, inline style and script only, `img-src data:`), and the renderer is
injected into the transcript view, not carried by the page. A fence in a slip shows its own
source.

Both halves matter. "Diagrams work" plus a slip showing raw mermaid is a worse outcome than never
having mentioned it. Draw in a slip with inline SVG; draw in a sentence with a fence.

## The environment a session already has

- **`CLAUDE_CODE_SESSION_ID` is injected into every Bash tool call** and equals the `sessionId` in
  `~/.claude/sessions/<pid>.json`, which is the `{id}` every route takes. `CLAUDE_PID` is beside
  it. Neither is in the `claude` process's own exec-time environment — only in the shells it
  spawns, which is exactly where they are wanted. Verified from inside a subagent's shell, where
  they still name the session the phone lists.
- **Inside OpenCode the same id is `OPENCODE_SESSION_ID`** (`ses_…`), in every shell its agent
  runs, and it too is the `{id}` every route takes — the phone lists OpenCode sessions as
  `provider: opencode`. `slip.py`, `answer.py` and the `deckhand` command read it when
  `CLAUDE_CODE_SESSION_ID` is not there.
- **A record outlives its process.** `~/.claude/sessions/<pid>.json` stays on disk after the
  session goes, so a record only counts when `ps` still shows that pid. The daemon does that
  join; anything reading those files directly has to do it too.
