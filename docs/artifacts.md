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
  .gitignore          # a single `*` — the folder ignores itself, so no repo gains a new entry
  artifacts/
    <id>.html         # the page. Written by the agent. Its <title> is the artifact's name.
    <id>.answer.json  # written by the daemon when the person answers. Absent until then.
```

In the project, not in `~/Library/Application Support/Deckhand/`, which is where every other
piece of Deckhand's state lives. This is the one exception and it is the whole design:

- An agent can write one with `Write`, list them with `ls`, read an old one with `Read`, and
  duplicate one with `cp`. No new tool, no MCP, no token, no discovery step — an agent knows
  its own cwd and nothing else is needed. "Agents can reuse earlier artifacts and edit,
  improve, duplicate them" costs exactly zero code because of this choice.
- Artifacts are about the project, and they outlive the session that wrote one. Keyed by
  session they would scatter one project's slips across every session that ever worked on it,
  and the second session would not find the first one's work.

`<id>` is a slug the agent picks and that a person could read: `release-check`, `palette-pick`,
`which-branch`. Duplicating an artifact is copying its file to a new slug.

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
window.deckhand.close()          // dismiss the viewer
window.deckhand.artifact         // { id, title }
window.deckhand.answer           // what was answered last time, or null
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

## How an agent uses one

Write the file, tell the person it is there, then read the answer:

```
.deckhand/artifacts/which-branch.html      <- Write
"I have put a question on your phone."
.deckhand/artifacts/which-branch.answer.json   <- Read, once it exists
```

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

## The demo set

Five pages under `demos/`, one per thing `consult-user-mcp` can ask, because that MCP is the
existing proof of which questions are worth asking from a phone: a confirm, a pick (single and
multiple), a text field, a form of several questions in sequence, and a set of sliders. They are
working artifacts, not mockups — copy one into a project's `.deckhand/artifacts/` and it runs.
