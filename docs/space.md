# The space

> What is open in the headset beside the sessions, and where — kept on the Mac so an agent can add to it

## What this is

`deckhand-xr` (`~/dev/multi-stack/deckhand-xr`) puts every live session around the person in a
Quest 3 as a **plane**; looking at one and speaking sends the words to it. Web pages and Mac
windows sit beside them as planes too. The **space** is all of that: which extra planes are open,
and the **pose** of every plane, sessions included.

The headset could have kept it. The daemon keeps it instead, for one reason: a session that has
just started a dev server should be able to put the page next to itself without the person
fetching it. That is `open_plane`, and the store exists so that tool has somewhere to write.

The code is `daemon/src/deckhand_daemon/space/`. The contract it answers is
`deckhand-xr/CLAUDE.md`, under *The wire this app relies on*; its vocabulary — space, plane,
focus, near, pose — is that file's.

## The wire

Every route needs `x-deckhand-token`.

- `GET /space` → `{rev, planes: [Plane], poses: {key: Pose}}`. `rev` rises on every change, so
  the headset polls and redraws only when it moved.
- `POST /space/planes` `{kind, url?, window?, title?, near?, by?}` → `Plane`, 201.
  `kind: web` needs an http(s) `url`; `kind: window` needs an integer `window` the helper lists.
  `near`, when given, must be a listed session, or 404. A `localhost`, `127.0.0.1`, `0.0.0.0` or
  `::1` host becomes this Mac's LAN address, port kept. `title` defaults to the url's host or the
  window's own title.
- `DELETE /space/planes/{id}` → 204, and the plane's pose goes with it. 404 for no such plane.
- `PUT /space/poses/{key}` `{x, y, z, yaw}` → 204. Keys are `session:<id>`, `plane:<id>`,
  `manager`, `projects`, `launcher`. Every number finite, and no further than 20 m from the floor
  origin. A `plane:` key for a plane that is not open is a 404.
- `GET /windows` → `[{id, app, title, w, h, cropped}]`, `GET /windows/{id}/frame` one JPEG,
  `GET /windows/{id}/stream?fps=&max=&q=` MJPEG, `GET /windows/{id}/hevc?…` the same window as HEVC
  off the Mac's hardware encoder (the query goes through whole, on all three). A browser window
  is its page alone: the helper crops to the AXWebArea, so `w`/`h` are the page's, `cropped` says
  so, input maps into the page, and `?whole=1` is the uncropped window for debugging. Passed through to `deckhand-windows` on
  `127.0.0.1:4181`, the Swift helper in `deckhand-xr/windows/`; a 503 with the reason when it is
  not running.
- `POST /windows/{id}/input` `{type: down|move|up|scroll|text|key, …}` → 204. The helper raises
  the window and drives the **real** cursor and keyboard, so a click lands in a browser exactly as
  one made at the Mac. The daemon then counts it as a headset beat, because the event it just
  caused reads as a key pressed at the laptop.
- `POST /presence/headset` → 204: the headset beats every 10 s while it is worn, and for 30 s
  after the last beat `GET /presence` answers `where: headset`, ahead of the laptop and the phone.
  For delivery it is not `laptop`, so `auto` still types; for an agent asking, it is the laptop's
  answer — the person reads the conversation on a pane. JJ's statusline goes to one short line on
  it.
- Every `/sessions` row carries `project: {key, color, parent, group}` — the repo the session is
  in, the colours JJ's statusline gives it (`sessions/project.py`, cross-checked against the
  script), and the group id its terminals share by default. The headset tints a terminal with
  `color` and groups a project's terminals under `group` while two or more are live and none has
  a kept pose — named here so the daemon can say who is in a group the headset never wrote down.
- `GET /sessions/{id}/space` → `{pose, group, beside}`: where that session stands, its group by
  the headset's rule, and every session, page and window in that group or opened `near` it
  (`space/around.py`). What the `space` tool hands an agent as `around_you`.
- `POST /space/sessions` `{near, path, provider?}` → 201 with the session: start one in `path`
  standing beside `near`, in its group. `POST /projects/session` does the starting, so the
  listing and the trust record gate it unchanged; a subfolder of a listed repo is taken as the
  repo. `space.json` keeps `beside: {new id: near id}`, and the headset stands a session with no
  pose of its own beside the one named there.
- `PUT /space/planes/{id}/near` `{near}` → 204: the headset handing a page or window to another
  session, or to nobody (`null`). A page the person opens with `near` set, or hands over this
  way, is **told** to that session down its socket (`prompts/space-given.md`), because what he
  says looking at it now goes there; a plane an agent opened beside itself carries its `by` and
  is not news to it.
- `GET /sessions/{id}/screen` → `{lines, at, styled, runs?}`: the pane as it stands, shared
  across polls for 0.5 s. It is what the headset's terminal plane shows — the prompt box and a
  pending permission question are on the screen and in no transcript. No pane is a 409, as
  `/focus` answers. `lines` is plain text either way. `styled: true` adds `runs`, one list per
  line of `{t, fg?, bg?, b?, f?, i?, u?, v?}` — text, colours as `#rrggbb`, bold, faint, italic,
  underline, inverse — adjacent cells of one style made one run. A default colour is left out;
  ANSI 0–15 come through the pane's profile (bold 0–7 drawn bright when it says so), 16–255 the
  xterm table, 24-bit as is. A double-width character is one run character, its placeholder
  cell dropped. `styled: false` is `it2 session read` (~0.13 s), which is all there is until
  iTerm's API is approved, and for a minute after it fails.
- `GET /terminal/theme?session=` → `{font: {family, size}, fg, bg, bold, cursor, selection,
  ansi: [16], lineSpacing, charSpacing, brightBold}`: what iTerm draws the pane with, colours as
  `#rrggbb` (null when the profile has none), the font as its PostScript name. With `session`
  and the API approved it is that pane's own profile; otherwise the default profile out of
  iTerm's preferences, ` (Light)` or ` (Dark)` colours by the Mac's appearance when the profile
  keeps both. Shared for 10 s.

**Approving the API is JJ's step, once, at the Mac.** iTerm asks by name whether a new client
may connect, with a dialog on the screen, and every API call waits until it is answered — so the
daemon never connects on its own. `just iterm-styles` connects as `deckhand` from a terminal, JJ
answers the dialog, and it writes `iterm-approved` in the data dir; the daemon reads that marker
on every call and needs no restart. Delete the marker to go back to plain text.

`Plane = {id, kind, url, window, title, near, by, at}`. `Pose = {x, y, z, yaw, pitch?, roll?, scale?, group?}` — metres in
the floor-origin space, angles in radians, scale 0.25–4. Planes whose poses share a `group` are one project to the
person — any mix of sessions, pages and windows — and move as one; the headset decides who joins,
by snapping one plane against another, and this only keeps the answer. State is `space.json` in the data dir, written whole through
`os.replace`.

- **The stream is relayed, never buffered.** It has no end. When the headset goes, the relay
  closes its side to the helper — in a background task, because Starlette cancels the stream on a
  disconnect and an await inside that cancelled scope would be cancelled too. Verified against a
  real uvicorn: the helper sees the connection drop.
- **localhost is rewritten, not refused.** A session writes `http://localhost:5173` because it is
  true where the session runs. In the headset it is true of the headset. The rewrite helps only a
  server bound to `0.0.0.0`, which is why the tools tell the agent to prefer the project's atlas
  dev hostname, `https://<slug>.atlas.local.jurrejan.com`, and say why.

## Why an agent may open planes and start sessions, and never close a session

`open_plane`, `close_plane`, `space`, `mac_windows` and `start_session` are in the MCP server and
the `deckhand` command. Every other refusal in `docs/agent-surface.md` stands — no `/control`, no
keyboard route, no `PUT /settings` or `/filters`.

`start_session` was a refusal until JJ asked (2026-10-14) for agents to bring sessions into the
space: to hand part of the work to another session, or to show him something running beside the
terminal he is talking to. It goes through `POST /space/sessions`, which is `POST /projects/session`
with a place to stand, so a session can only start in a folder the listing names and Claude Code
already trusts. It starts with no task; the agent briefs it with `say_to_session`, which arrives
as an agent and carries none of the person's authority.

A plane is furniture. Opening one starts no process and speaks to nobody; closing one stops
nothing. What the person says *at* a web or window plane still goes to its `near` session through
that session's own routes, so the filter chain, the orders and the delivery record apply exactly
as they do from the phone. The worst an agent can do here is clutter the room.

A session is not furniture. Closing one is `/control exit`, pressed by the person on that
session's own plane, and an agent has no way to it: a session's plane comes from the listing and
is never kept in the space, so `DELETE /space/planes/{id}` has nothing to name it by. Like every
other refusal on the agent surface, this is absence rather than a fence, and the agent token in
`docs/agent-surface.md` is still what would make it real.

Input into a Mac window is the person's hand and is **not** an agent tool. It drives the real
cursor and keyboard, the keyboard route's authority, so an agent with it would be the person by
another name. The headset sends it; the MCP server and the `deckhand` command do not have it.
