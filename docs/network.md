# Every machine on the network, not just this one

> A plan. Nothing below is built yet.

Deckhand lists the Claude Code sessions running on this Mac. There are two other machines on the
network that run Claude Code — the Ubuntu server and the Fractal PC — and the phone cannot see
them. This is what it would take, and what it must refuse.

## What is actually out there

Measured on 2026-09-11, not assumed. The homenetwork doc is wrong about Ubuntu: it has `claude`.

| Machine | `claude` | `~/.claude/sessions` | Pane | `uv` | Role |
|---|---|---|---|---|---|
| M2 Pro | 2.1.259 | 20 records, live | iTerm | yes | **the daemon** |
| Ubuntu (`mbp-ubuntu`) | 2.1.261 | dir exists, 0 live; 10 project histories | tmux | no | a hand |
| Fractal (`FRACTAL`) | 2.1.251 | 2 records, both stale | tmux (psmux) | yes | a hand |
| MBP 15 (`.120`) | none | absent | — | — | out of scope |
| QNAP NAS | none | — | — | — | out of scope |

Worth saying plainly: **Ubuntu has no live session right now and Fractal's two records are six days
stale.** This builds a road before there is traffic on it. That is a reason to build it small, not
a reason not to build it.

## The three facts the design hangs off

**Claude Code already namespaces machines.** Fractal's record says `"pidDomain":"win32:fractal"`,
this Mac's says `"darwin"`. More usefully, `sessionId` is a UUID, so it stays the primary key and
**not one route URL changes**. `/sessions/{id}/turns` works the same whichever machine the session
is on.

**The inbox lane cannot be reached from off the machine.** `deliver._through_socket`
(`deliver.py:203-222`) opens `AF_UNIX` on the path in the record's `messagingSocketPath`
(`/tmp/cc-socks/<pid>.sock` here, `\\.\pipe\LOCAL\cc-msg-…` on Fractal) and authenticates with a
`0600` key file beside the record. There is no listener on either end. A process on that machine is
not an optimisation — it is the only way in.

**The daemon is already most of the way to running elsewhere.** `sessions_dir()` (`sessions.py:49`)
and `projects_dir()` (`reading/transcripts.py:70`) both route through `DECKHAND_CLAUDE_HOME`, and
`live_sessions(iterm_only=True)` already keeps every session when there are no panes **at all**
(`sessions.py:204`) — so a machine with no iTerm lists correctly today, untouched.

## The shape

One new noun. **A machine** is a computer on the network that runs sessions. **A hand** is this
same daemon in `--hand` mode on a machine that is not this Mac: it reads, and it writes one thing
into one socket. The daemon on the M2 stays the daemon, stays the only thing the phone talks to,
and keeps every decision.

```
phone ──http──► daemon (M2)  ── ssh -L ──► hand (Ubuntu)
                   │                        hand (Fractal)
                   └ filters, orders, transcription, briefings, APNs, the manager
```

That split is not arbitrary. **The hand holds what only exists on its own disk; the daemon holds
everything that decides.** A hand has no filter chain, no orders, no settings, no utt, no APNs key
and no manager. It cannot be asked to make a judgement, because it has nothing to judge with.

### Transport

The hub opens one SSH process per machine that both forwards a port and runs the hand:

```
ssh -L 4181<n>:127.0.0.1:4181 <alias> 'exec deckhand-daemon --hand'
```

The hand binds `127.0.0.1` only. **Nothing about this puts a session's inbox on the LAN** — no
listening port on Ubuntu or Fractal, no Windows firewall rule (all three profiles are enabled
there), no second token to type. Authentication is the key-only SSH mesh that already works 5×5
across these hosts.

It also means **no service to install**. The hand's lifetime is the SSH process's lifetime; when
the daemon restarts, the hands restart. There is no systemd unit and no Scheduled Task, because a
hand holds no state worth surviving — all state is on the M2. The daemon supervises the subprocess
with backoff and polls `/health` for readiness, because the forward is up before the hand has bound.

`x-deckhand-token` still guards every hand route; the daemon reads each hand's token over the same
SSH channel on first connect. Belt and braces, and no new surface.

> Considered and rejected: plain HTTP on the LAN. `.local` names resolve fine here
> (`mbp-ubuntu.local` → `.121`, `fractal.local` → `.197`), so DHCP drift is not the objection —
> the objection is that it puts "write into this session's inbox" on the network, behind one
> shared secret, on a machine whose firewall would need opening.

### What a hand serves

Read, plus exactly one primitive.

| Serves | Why |
|---|---|
| `GET /health`, `GET /sessions` | its own machine's records, `ps`, no panes |
| `GET …/turns`, `/raw`, `/context`, `/commands`, `/files`, `/file` | files only on that disk |
| `GET /sessions/links` | edges are within a machine by construction — `AF_UNIX` cannot cross one |
| `GET /projects` | folders on that disk, plus that machine's `~/.claude.json` trust list |
| `GET\|POST …/artifacts…` | a slip is a file in `<cwd>/.deckhand/artifacts` |
| `POST …/queue/clear` | writes that machine's queue file |
| `POST …/deliver` | **new.** Exact text → that session's socket. No filters, no orders, no record. |

### What a hand refuses, and how

By absence. The router is never mounted, so the route 404s:

`/settings` · `/orders` · `/filters` · `/briefings` · `/summary` · `/audio` · `/say` · `/notify` ·
`/image` · `/live/token` · `/manager` · `/focus` · `/control` · `/name` · `POST /projects/session`

The last four are pane work. **For v1 a remote session is socket-only**: you can read it and speak
to it, and focus, stop/compact/clear, `/rename` and image paste are simply not there. Both machines
run tmux and Claude Code even records a tmux target (Fractal's says `main-2:@2.%3`), so this is a
decision rather than a limit — see *Left out*.

`POST /projects/session` is on that list for a harder reason than the others: `starting.start()` is
`it2` from end to end — `it2 window new` for the handle, `it2 session run` to launch, `it2 session
list --json` to find the pane (`starting.py:109`, `:127`, `:150`). There is no fallback path in it
to disable. **Starting a session on a remote machine is not a flag, it is a second backend**, and it
arrives with the rest of the pane work or not at all. The phone lists remote folders; it opens them
only on this Mac.

And the standing invariant gets a second reason to fire: **the keyboard route on a remote session
returns 409, never a fallback.** It already does this when a session has no pane
(`deliver.py:66-81`). A remote session has no pane. Nothing new to write, and nothing to relax.

## Three stores key on the wrong thing

This is the part that will bite, and it bites before any network code runs. Three stores key on
something that is not the `sessionId`, and every one of them can collide across machines:

| Store | Keyed by | Where | Fix |
|---|---|---|---|
| `filters.json` | session **name** | `filters/config.py:29-30` | `machine/name` |
| `settings.json` | absolute folder **path** | `settings/wants.py:77-78` | `machine:path` |
| iOS favourites / hidden | session **name** | `Preferences.swift:40-41` | `machine/name` |

Names are folder-derived (`daemon-9d`, `jurre-28`), so two machines produce the same name easily.
Each needs a one-shot migration that prefixes every existing key with this Mac's name. `POST /name`
rekeys `filters.json` and has to rekey the new shape.

A fourth, in Swift: **`ProjectGroup.of` buckets on `cwd` and its `id` is the path**
(`Rail/ProjectGroup.swift:36-41`), abbreviating `/Users/jurrejan` → `~`. `/Users/jurrejan/dev/x`
and `/home/jurrejan/dev/x` would both render `~/dev/x` and silently merge into one project block.
The key becomes `(machine, path)`.

A fifth, internal: `sessions._current` / `_retired` are keyed by **pid** (`sessions.py:170-171`).
pids collide across machines by definition. They stay correct only because each hand runs its own
process with its own dicts — which is an argument for the hand over any design where the M2 reads
remote files directly.

## Where the code goes

`deckhand_daemon/` holds 15 loose `.py` files against a 16-file cap, and `sessions.py` is 348 lines
against a 400 cap. So the new code is a package, and `sessions.py` splits first.

| New | Job |
|---|---|
| `fleet/machines.py` | the registry — name, ssh alias, local port; a `machines.json` in `<data>/` |
| `fleet/link.py` | the ssh subprocess, readiness poll, restart backoff, token fetch |
| `fleet/proxy.py` | `call(machine, method, path, …)` over the existing `httpx[http2]` dep |
| `fleet/merge.py` | merged `/sessions`, `/sessions/links`, `/projects`; `where(session_id) → machine` |
| `fleet/routes.py` | `GET /machines` |

| Changed | How |
|---|---|
| `sessions.py` | `Session.machine: str`; emitted by `to_json()`; pane half split out |
| `app.py` read routes | resolve `session_id → machine`; local → today's code, else proxy |
| `saying.py` | the one `deliver.deliver(...)` call becomes `fleet.deliver(...)` — the pipeline above it does not move |
| `summarize.py` | pulls turns through the fleet layer instead of local files; the SDK still runs here |
| `push/__init__.py:137` | passes the **session's** machine as `mac` instead of `config.base_url()`'s hostname |
| `manager/tools.py` | `listing()` gains the machine; `find(wanted)` disambiguates by name across machines |
| `app.require_token` | `secrets.compare_digest` instead of `!=` (`app.py:39`) — the daemon is about to hold one token per machine and compare far more of them |
| `/health` | gains a `machines` array — name, reachable, session count, last error |

### The manager

Its eleven tools divide cleanly, which is the sign the seam is in the right place. Seven are reads
that go through the fleet layer and then span every machine for free: `list_sessions`,
`read_session`, `list_projects`, `read_settings`, `read_context`, `history`, `show_on_phone` (the
last touches no machine at all — it writes a `command` entry into the conversation file,
`doing.py:133-152`).

`say_to_session` already hard-codes `route="socket"` (`doing.py:60`) — the manager's central
refusal, written before any of this, and exactly the call the fleet layer needs. It works remotely
unchanged.

`set_orders` and `set_switch` write hub state and stay put. `focus_session` and `start_session` are
`it2` (`doing.py:85-107`, `:155-163`) and are therefore **absent on a remote session**, the same
way and for the same reason as the routes above them. The manager's own rule does not move: it
still never types into a pane, and now there are machines where no pane exists to type into.

One free lunch worth checking before writing code: `list_projects` already queries atlas on
`127.0.0.1:47891`, and atlas already catalogues `/home/jurrejan/development` and `C:\dev` on the
other two machines (`atlas hosts list`). Remote project listing may need no hand route at all.

The Live Activity needs **no wire change at all**: its attributes already carry `mac: String`
(`LiveActivity.swift:60-73`) and the widget already draws it in the Lock Screen footnote
(`DeckhandWidgets.swift:156`). Today it means "which Mac is serving you" and is always `m2-2`.
Repointing it at the session's machine is one line and the card starts telling the truth.

## The phone

The phone pairs to exactly one address — `ServerSettings` is a single `host` + `token` defaulting
to `m2-2.local` (`ServerSettings.swift:5-9`) — and all ~30 call sites go through `settings.client()`.
**The phone never learns a hand exists.** Machine is a field on the data and a way to slice the list.

- **A machines page, one swipe past the manager.** `ManagerShell`'s `open: Bool` becomes an index
  across three children (`ManagerShell.swift:46-58`, settle threshold `:102-111`). `MachinesView`
  goes in `deckhand/Views/Manager/`, which holds 4 files.
- One row per machine: the name, its session count, and reachability as a `StateWord` — `.online`,
  `.off` and `.err` already exist (`Model.swift:26-33`). Tap to filter the rail.
- **No colour per machine.** In this app busy/idle is a *word*, not a colour (`StateWord`), and
  `Palette.tint` is the only accent. A machine reads as a word plus `DotGlyph.forName`.
- `Session.machine` must be **Optional** — the synthesised decoder only tolerates a missing key on
  an optional (`Models.swift:26-31`), so a non-optional field makes an older daemon's whole listing
  fail to decode.
- The filter lives on `AppModel` beside `showsHidden` (`Model.swift:140-142`), not in the view:
  `SessionListView.swift` is 286 lines against a 300 warn.
- `SessionLinkTrails` is untouched. A trail whose ends are on different machines cannot exist.

## Order

**Spike first, and it is cheap.** Start one session on Ubuntu in tmux, point `DECKHAND_CLAUDE_HOME`
at it, and check two things: that `live_sessions()` produces a correct listing with no panes, and
that a raw `deliver._through_socket()` write lands in that session's inbox. Everything here hangs
off those two, and they are one afternoon to prove or disprove.

1. **The seam, all local.** `machine` field, `fleet/` with only this Mac registered, the three key
   migrations, the `sessions.py` split. One machine, everything still works, one new field on the wire.
2. **The hand, on Ubuntu.** `--hand` mode, route filtering, `POST /deliver`, the ssh link, proxy and
   merge. POSIX, so the existing code nearly runs as-is. A `just install-hand <alias>` recipe that
   rsyncs `daemon/` and runs `uv sync` — Ubuntu has no `uv` yet.
3. **Fractal.** Two real unknowns, both inside two functions: liveness without `ps`
   (`sessions._processes()` — use the record's `procStart` FILETIME against `Get-Process`, which is
   *better* than the current `ps | grep claude` heuristic), and writing to `\\.\pipe\LOCAL\cc-msg-…`
   instead of `AF_UNIX` (`deliver._through_socket()`).
4. **The phone.** The machines page, the filter, the preference migration, the `mac` repoint.

## Left out, and when to add it

**Pane control on a remote machine**, and with it `POST /projects/session`, `focus_session` and
`start_session`. Both hands have tmux and Claude Code records the target, so focus,
stop/compact/clear and `/rename` are reachable via `tmux send-keys`. Add it when reading a remote
session stops being enough — but note that `deliver.py:32-41` spells keys as CSI-u escape sequences
for a measured reason, and that reason has to be re-proven against tmux rather than assumed. This
is one piece of work, not four: every one of them is the same missing backend.

**Cross-machine session links.** Not left out — impossible. `AF_UNIX` does not cross a machine, so
no such edge exists to draw.

**A hand as a service.** Add a systemd unit only if it turns out you want sessions listed while the
M2 is asleep. Today the M2 is the only thing the phone can reach, so a hand outliving it is useless.

**Anything on the NAS or the MBP 15.** Neither runs `claude`.

## Glossary additions

| Term | Meaning |
|---|---|
| **machine** | a computer on the network that runs sessions. The word in the app and in code alike — `host` is already taken by the daemon's own address in `ServerSettings`. |
| **hand** | this daemon in `--hand` mode on a machine that is not this Mac. Reads its own disk, writes one socket, decides nothing. |
