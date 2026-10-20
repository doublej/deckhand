# Artifacts

> One page, written by a session, read on the phone, answered by the person

An artifact is a single HTML page a Claude Code session writes for the person holding the
phone. It is how a session asks something that a sentence cannot ask well: pick one of these
four, fill in these six fields, confirm this before I do it, choose a number on this slider.
The person answers on the page and the answer goes back into the session.

**On the phone it is called a slip.** That is the tab's name and the word to use when you tell
the person there is one waiting — "I have put a slip on your phone", never "an artifact". The
folder, the endpoints and this document keep the older word because they are the plumbing, and
"page" in here means the HTML itself.

It is deliberately less than Claude's own artifacts. One page, no tabs, no router, no history,
no network, phone-shaped only, and in Deckhand's own visual language rather than its own. The
thing it has that a spoken reply does not is **structure**: a form returns fields, not prose.

## Where they live

```
<the session's cwd>/.deckhand/
  .gitignore              # a single `*` — the folder ignores itself, so no repo gains an entry
  artifacts/
    <session id>/         # this session's own slips. Where a slip written today goes.
      <id>.html           # the page. Written by the agent. Its <title> is the artifact's name.
      <id>.answer.json    # written by the daemon when the person answers. Absent until then.
    <id>.html             # flat: a slip belonging to the folder, listed by every session in it.
```

In the project, not in `~/Library/Application Support/Deckhand/`, which is where every other
piece of Deckhand's state lives. This is the one exception and it is the whole design: an agent
can write one with `Write`, list them with `ls`, read an old one with `Read`, and duplicate one
with `cp`. No new tool, no MCP, no token, no discovery step — an agent knows its own cwd and
nothing else is needed. "Agents can reuse earlier artifacts and edit, improve, duplicate them"
costs exactly zero code because of this choice.

**Two scopes inside that folder, and a session's own is the default.** Flat was the only scope
once, on the argument that slips are about the project and outlive the session that wrote one.
That is true of some of them, and it made the rest wrong: three sessions open in one repo listed
the same slips three times, and answering one delivered the answer into whichever session the
phone had open rather than into the one that asked — the route in is
`/sessions/{id}/artifacts/{aid}/answer`, so the session is whichever tab you came from. A slip
under the session's own id goes back to the session that asked it.

What the old scope was for survives the change:

- The store is still in the project, so `ls ..` from a session's folder finds a sibling
  session's work and `cp` still duplicates it. Only the **phone's listing** narrowed, and it
  narrowed to this session's own plus the folder's — never to a stranger's.
- **A slip meant for the folder is still written flat**, and every session working there lists
  it. That is the right shape for a question about the project rather than about a piece of
  work: "which branch does this repo release from", not "which branch should *this* land on".
- Nothing had to move. Every slip written before scopes existed is a flat one and goes on
  working as the folder's.

A session's listing carries both, and says which is which: `shared` is true for a slip that
belongs to the folder. Where the same id exists in both, the session's own wins — a page it
wrote for itself cannot be displaced by one it did not write.

`<id>` is a slug the agent picks and that a person could read: `release-check`, `palette-pick`,
`which-branch`. Duplicating an artifact is copying its file to a new slug. `<session id>` is held
to exactly the same rule, because it is a path segment in a URL before it is a folder name.

## What the page may contain

Inline HTML, CSS and JS. Nothing else — no network of any kind, enforced by a CSP the app
injects and not by good manners:

```
default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline';
img-src data:; font-src data:; form-action 'none'; base-uri 'none'
```

So: no CDN, no Google Fonts, no `fetch`, no remote image, no form post, no navigation. An
artifact is HTML written by an agent and rendered on a person's phone; it gets to draw and to
answer, and that is all. Pictures are `data:` URIs or SVG. This is the security boundary of the
whole feature and it is not negotiable by an artifact — a page that declares its own CSP only
narrows what it may do, because browsers intersect policies rather than replace them.

The app also injects a stylesheet of Deckhand's own tokens before the page loads, so an
artifact that writes plain semantic HTML already looks like the app. Use the custom properties;
do not re-pick colours.

## Answering

One function, injected before the page runs:

```js
window.deckhand.respond(value)   // any JSON value. May be called more than once.
window.deckhand.keep(value)      // the unsent draft, kept on the phone. keep(null) drops it.
window.deckhand.close()          // dismiss the viewer
window.deckhand.artifact         // { id, title }
window.deckhand.answer           // what was answered last time, or null
window.deckhand.draft            // what keep() last held, or null
```

`respond` hands the value to the app, which sends it to the Mac. The daemon then does two
things, and both matter:

1. Writes `<id>.answer.json` beside the page — `{"id", "answeredAt", "value"}`. An agent that
   is waiting can simply read this file.
2. Delivers a message into the session by the person's configured route, the same path
   speaking takes. An agent that has stopped is woken by it rather than having to poll.

The answer is the person's own, so it travels as the person's words, not as a peer agent's.

## Reading back what was answered

`window.deckhand.answer` is the value the person last responded with, in exactly the shape it was
responded with, or `null` where nobody has. It is in place before the page's first line runs — the
app fetches it with the HTML and draws neither until both are in — so a page reads it while it is
building its controls and never has to repaint.

**A page is expected to use it.** An answered page that reopens showing an empty form is lying: the
row that opened it says "answered". So read `window.deckhand.answer` once, and where it is not
`null`, prefill from it — tick the option that was picked, fill the fields that were filled, put the
sliders where they were left. Then let the person change their mind and call `respond` again; the
Mac simply rewrites the answer file. The value is not frozen, so it can be edited in place.

It is the page's own value, so the page is the only thing that can read it: Deckhand never inspects
the shape and never normalises it. A page whose controls have changed since it was last answered is
the page's problem to survive — treat an unexpected shape as nothing answered.

Under it is one request, for agents that want the same fact from the Mac:

```
GET /sessions/{session_id}/artifacts/{artifact_id}/answer   ->  {"value": <whatever was responded>}
```

`{"value": null}` is "nobody has answered", not an error. A missing page is still a 404.

## Drafts

The web view keeps nothing (a non-persistent store), so whatever a page holds and has not sent
dies with the screen: the close button, a call, the app relaunching. `window.deckhand.keep(value)`
is the way out — the phone stores the value's JSON under the slip's id (`SlipDrafts`, up to
256 KB) and hands it back as `window.deckhand.draft` the next time the slip opens. A send that
went clears it. **Prefill from `draft ?? answer`**: a draft only exists when it is newer.

On the phone and only there: a draft is what this phone has done, not something the session is
owed, so nothing reaches the Mac or the session until `respond`. An aloud slip's cards keep their
own draft the same way, with no page involved.

## How an agent uses one

Write the file, tell the person it is there, then read the answer:

```
.deckhand/artifacts/$CLAUDE_CODE_SESSION_ID/which-branch.html      <- Write
"I have put a question on your phone."
.deckhand/artifacts/$CLAUDE_CODE_SESSION_ID/which-branch.answer.json   <- Read, once it exists
```

`CLAUDE_CODE_SESSION_ID` is in every Bash call Claude Code makes and is the session id the daemon
knows, so an agent needs no discovery step to find its own folder. Drop the segment to write a
slip that belongs to the project instead.

Nothing registers an artifact and nothing cleans one up. A slip with no answer file beside it
is open; one with an answer beside it has been answered, and can be asked again by deleting the
answer.

An open slip is also the one thing the phone says without being asked. The session listing carries
`artifacts_waiting` and `artifacts_answered`, so the session's row on the overview says how far
this project has got with its slips — "1 of 3 slips waiting" — beside how far it has got with what
the person asked *it* for, and the session's summary offers the newest waiting slip as the thing to
press. An agent still tells the person it is there — a phone in a pocket says nothing — but nobody
has to open the Slips tab to find it.

## Talking at a page

A phone dictates better than it types, so two things the app offers over every page are worth
knowing about if you are writing one.

**A field can be spoken into.** While an `<input>` (text, search, url, email, tel, number, or no
type at all), a `<textarea>` or anything `contenteditable` has focus, a Say control appears under the
page. The words are appended to whatever the field already holds — never over it — and the app then
dispatches a real `bubbles: true` `input` event on the element. So **gate on `input`, not on
`keydown`**: a page that watches for keystrokes will see a field fill up and not notice. `change` is
deliberately not sent — the person may say more, or type. A `type="password"` field is not offered
dictation at all.

**A selection can be commented on.** While something is selected in the page, the hold-to-talk mark
appears instead, and what the person says lands on the review card with the selected passage quoted
above it and the slip named by title and slug. That is a remark about your page on its way to the
session, not an answer: it never goes through `respond`, and a page neither sees it nor can stop it.

Both are driven by a small script the app injects alongside the bridge, which listens for
`selectionchange`, `focusin` and `focusout` and reports only *whether* the page is holding a
selection or a focused field — never the text. A page that tears those listeners off loses itself
the controls, the same way a page that paints nothing loses itself a screen.

## A slip answered by talking

A phone dictates better than it types, and an agent with six questions had two bad options: six
textareas on a page, or six sentences in a row in the session. The third is a page that **declares**
its questions instead of only drawing them:

```html
<script type="application/json" id="deckhand-aloud">
{ "questions": [
  { "id": "scope", "ask": "How far should this go?", "hint": "Reads first, writes later." },
  { "id": "deadline", "ask": "Is there a date this has to be done by?" }
] }
</script>
```

The app reads that block out of the HTML and draws **one card per question with its own talk mark**
— the same `TalkControl` and `TalkMark` the session page uses, so hold-versus-tap is the gesture the
person already chose. Words land under whatever the card already holds, never over it, and every
card carries a field as well, because an answer with one wrong word in it should not need saying
twice.

Three things make this worth doing rather than a second page format:

- **The block is the page's only source of truth.** `demos/aloud.html` renders *itself* from it, so
  the questions exist once. Edit the JSON and both renderings change; there is nothing to keep in
  step by hand.
- **The page is still a page.** It renders in a browser, it passes `demos/check.py`, and an app that
  has never heard of any of this shows it as a form and sends back the same answer. Everything that
  can go wrong with the block — missing, malformed, empty, a question with no id — lands on the same
  side: the app draws the HTML. A page that gets it wrong is a page that works.
- **The answer is the form answer.** `{"answer": {id: words}, "completedCount": n}` — what `ask`
  `type: "form"` comes back with and what `demos/form.html` already sends, so nothing new has to be
  learned to read one. A question nobody answered is left out rather than sent empty, and half the
  questions can be sent now and the rest added later; the Mac just rewrites the answer file.

Copy `demos/aloud.html`, change the title and the block, and that is the whole of writing one.

## A slip that is not a question

Everything above asks something. A **logbook** does not: it is the running account of a job too
long to say in a sentence, locked on the phone so the person can see where it has got to without
having to ask. `skills/deckhand/scripts/logbook.py` writes one, `demos/logbook.html` is the page,
and four decisions in it are each the fix for something a hand-rolled one got wrong.

- **Its state lives beside the page**, as `<slug>.log.json` in the same folder, and the page is
  rewritten whole from it on every command. A page that must be *edited* to be appended to costs
  a rewrite per entry, and a logbook costing that stops getting entries by the third one.
- **It is written flat, so it belongs to the folder.** The one slip whose default scope is not
  the session's own, for the same reason that scope exists elsewhere: a question has to come back
  to whoever asked it, while a job outlives the session working it — compacted, cleared,
  restarted, handed over. Flat is what lets the next session append to the same book by running
  the same command in the same directory, with nothing to discover and nothing to be told.
- **Rewriting it does not clear the answer.** `slip.py` deletes `<slug>.answer.json` when it
  rewrites a page, because rewriting a question is asking it again. Rewriting a logbook is the
  same page saying more, so a note the person left on it survives every entry appended after.
- **Both files land with `os.replace`.** A question page is written once; this one is written
  while the phone may be fetching it, and half a page is a broken slip rather than an error.

The page renders itself from one `id="deckhand-logbook"` block, the arrangement `aloud.html`
already uses — so the markup exists once, in the demo `demos/check.py` gates, rather than being
concatenated in Python where nothing would check it. Twelve entries are drawn and the rest
counted, because a phone is a phone; the state file keeps all of them, and the counts at the top
are over all of them.

That it answers at all is not a contradiction. The field at the bottom is a note back, in the
shape a `text` ask returns, so someone reading "blocked on the export" on a train can say what to
do instead without opening a laptop — and a page nobody can reply to is a page they end up
replying to by ringing the person who wrote it.

## The demo set

Seven pages under `demos/`. Five are one per thing `consult-user-mcp` can ask, because that MCP
is the existing proof of which questions are worth asking from a phone: a confirm, a pick (single
and multiple), a text field, a form of several questions in sequence, and a set of sliders. The
other two have no `consult-user` equivalent because they only make sense on a phone — `aloud.html`
and `logbook.html`. They are working artifacts, not mockups — copy one into a session's
`.deckhand/artifacts/<session id>/` and it runs, though those last two are better written by the
scripts that own them.
