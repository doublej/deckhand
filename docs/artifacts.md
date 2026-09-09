# Artifacts

> One page, written by a session, read on the phone, answered by the person

An artifact is a single HTML page a Claude Code session writes for the person holding the
phone. It is how a session asks something that a sentence cannot ask well: pick one of these
four, fill in these six fields, confirm this before I do it, choose a number on this slider.
The person answers on the page and the answer goes back into the session.

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
  session they would scatter one project's pages across every session that ever worked on it,
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
```

`respond` hands the value to the app, which sends it to the Mac. The daemon then does two
things, and both matter:

1. Writes `<id>.answer.json` beside the page — `{"id", "answeredAt", "value"}`. An agent that
   is waiting can simply read this file.
2. Delivers a message into the session by the person's configured route, the same path
   speaking takes. An agent that has stopped is woken by it rather than having to poll.

The answer is the person's own, so it travels as the person's words, not as a peer agent's.

## How an agent uses one

Write the file, tell the person it is there, then read the answer:

```
.deckhand/artifacts/which-branch.html      <- Write
"I have put a question on your phone."
.deckhand/artifacts/which-branch.answer.json   <- Read, once it exists
```

Nothing registers an artifact and nothing cleans one up. A page with no answer file beside it
is open; a page with one has been answered and can be asked again by deleting the answer.

## The demo set

Five pages under `demos/`, one per thing `consult-user-mcp` can ask, because that MCP is the
existing proof of which questions are worth asking from a phone: a confirm, a pick (single and
multiple), a text field, a form of several questions in sequence, and a set of sliders. They are
working artifacts, not mockups — copy one into a project's `.deckhand/artifacts/` and it runs.
