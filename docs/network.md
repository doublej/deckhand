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

## Atlas already knows the machines

Do not build a machine registry. Atlas has one, it is correct, and it is the reason this plan got
smaller after the first draft.

`shared/hosts.json` (version 1) holds exactly what the fleet layer needs, and `atlas hosts list`
prints it:

| Field | m2 | fractal | ubuntu |
|---|---|---|---|
| `label` | `M2 Pro` | `Fractal` | `Ubuntu` |
| `ssh` | `null` | `fractal` | `ubuntu` |
| `root` | `~/dev` | `C:/dev` | `/home/jurrejan/development` |
| `os` | `darwin` | `win32` | `linux` |
| `role` | `primary` | `satellite` | `deploy` |

The ssh **alias** is stored, not an IP — the same decision `config.base_url()` made for its own
`.local` name, and the same reason. `os` is there too, which is what picks the liveness and socket
code path on a hand. `label` is the word the phone's machines page draws; `id` is what the wire
carries.

**Those six fields are now a named contract.** `shared/CLAUDE.md` records that `hosts.json` has a
consumer outside the atlas repo and that `id`, `label`, `ssh`, `root`, `os` and `role` are names to
keep — because a rename here breaks a repo that will not fail to compile over there. Deckhand
depends on those six and no others; `node`, `agent` and `skipGit` belong to atlas's scan agent and
are never read here. If that ever changes, say so in atlas rather than reaching for the field.

Two consequences, both subtractions:

- **`fleet/machines.py` shrinks to a reader.** No `machines.json`, no second list of the same three
  machines to keep in step with the first.
- **A hand serves no `/projects` route at all.** `/api/projects` already returns 504 projects across
  all three machines — 450 on the M2, 28 on Fractal, 26 on Ubuntu — with `host` on every one, and
  `hosts[]` carrying `status` (`ok` / `unreachable`), `scannedAt` and `projectCount`. Deckhand's
  `GET /projects` merges atlas's answer instead of asking three machines itself.

Atlas's remote reach is a **one-shot scan** — `ssh <alias> <node> ~/.atlas/atlas-scan.mjs`, result
cached — not a live connection, so the SSH forward below stays deckhand's own. That is the right
line: **atlas owns which machines exist, deckhand owns the live link to them.**

Two things atlas learned the hard way that this plan inherits rather than rediscovers:

- **`-o ConnectTimeout=4 -o BatchMode=yes` on every ssh invocation.** `remoteScan.ts:25` carries the
  reason: *a powered-off DHCP box otherwise hangs the TCP connect for ~75 s.* Deckhand asks
  "is this machine up" on every session listing, so without this a sleeping Ubuntu stalls the
  phone's list for over a minute. This is the single cheapest bug to avoid here.
- **Windows OpenSSH has no `ControlMaster`** (`remoteScan.ts:20-21`), which is why atlas never built
  connection reuse. It does not affect the forward below — multiplexing and port forwarding are
  different features, and `-L` is fine — but it does mean *one long-lived connection per machine* is
  the only cheap shape available. Which is what this plan already does, now for a second reason.

**Read the files, not the API.** Atlas's own docs name the shared JSON as the surface for the
registry — atlas-picker, in Rust, already reads it that way — and the API carries a staleness the
file does not: `shared/hosts.json` is an ESM import, so the daemon holds its **startup copy** and
`PUT /api/hosts` answers `restartRequired: true`. A registry edit is invisible over HTTP until
`bun run daemon:reload`. Reading the file also means the fleet layer does not fall over when the
atlas daemon is down, which matters because deckhand's is the one that has to keep answering.

What atlas does not have yet, and what has been asked of it, is in *Asks of atlas* at the end.

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
| `filters.json` | session **name** | `filters/config.py:29-30` | `machine/name` — **done**, `edcaadd` |
| `settings.json` | absolute folder **path** | `settings/wants.py:77-78` | **not done, on purpose** |
| iOS favourites / hidden | session **name** | `Preferences.swift:40-41` | `machine/name` |

Names are folder-derived (`daemon-9d`, `jurre-28`), so two machines produce the same name easily.
Each needs a one-shot migration that prefixes every existing key with this Mac's name. `POST /name`
rekeys `filters.json` and does rekey the new shape.

**`settings.json` is left keyed by path**, and this is a decision rather than an oversight. The
three roots are `/Users/jurrejan/…`, `/home/jurrejan/development/…` and `C:/dev/…`: the key is
already unique because the namespaces are disjoint, so prefixing it would buy nothing and cost a
migration plus eight call sites, two of which hold only a folder string and would have to be
given a machine to pass on. **Add it the day a second host with an overlapping root joins
atlas's registry** — in practice a second Mac, `mbp15` being the obvious one — because from then
on `/Users/jurrejan/dev/x` names two folders and one switch would quietly set both.

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
| `fleet/machines.py` | reads atlas's registry and adds one field of its own — the local forward port |
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

`list_projects` already queries atlas on `127.0.0.1:47891`, and atlas already catalogues all three
machines. It spans the network the moment the machine registry does, with no change to the tool.

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
- **Clamp `label` on the way in.** It is display copy the phone renders verbatim, and atlas
  validates neither its length nor its emptiness — it is hand-editable in `hosts.json` and through
  the `/system` console's registry editor. Atlas has no use for that validation and will not add
  it, which is the right call on their side and an obligation on this one: fall back to `id` when
  it is blank, and truncate rather than let a long one push the row's state word off the screen.
- `Session.machine` must be **Optional** — the synthesised decoder only tolerates a missing key on
  an optional (`Models.swift:26-31`), so a non-optional field makes an older daemon's whole listing
  fail to decode.
- The filter lives on `AppModel` beside `showsHidden` (`Model.swift:140-142`), not in the view:
  `SessionListView.swift` is 286 lines against a 300 warn.
- `SessionLinkTrails` is untouched. A trail whose ends are on different machines cannot exist.

## Order

**The spike is done, and both halves passed.** Run 2026-09-11 against a real session started in
tmux on Ubuntu (`claude --name spike-probe`, 2.1.261, in an already-trusted folder):

- **The join works untouched.** `ps -eo pid=,tty=,command=` parses the same on Linux (tty reads
  `pts/0`), and the listing came back correct with *no pane data at all* — which is what
  `live_sessions` already does when there are no panes anywhere.
- **The inbox lane works untouched.** A raw `user` frame carrying the `peerToken` from the sibling
  `.key` file produced a `queue-operation`/`enqueue` *and* a consumed `user` entry wrapped in
  "Another Claude session sent a message" — the peer framing intact, and with no
  `<cross-session-message>` header, exactly as `links/edges.py` says a sender that is not Claude
  Code itself behaves.

**A hand on Linux is a port, not a rewrite.** Three things the spike corrected, each of which
would otherwise have been a quiet bug:

| | macOS | Linux | Windows |
|---|---|---|---|
| socket | `/tmp/cc-socks/<pid>.sock` | **`/run/user/1000/cc-socks/<pid>.sock`** | `\\.\pipe\LOCAL\cc-msg-…` |
| `procStart` | a date string | clock ticks (`"1343642930"`) | FILETIME (`"134330…"`) |
| `pidDomain` | `darwin` | `linux:<machine-id>:pid:[…]` | `win32:fractal` |

The socket is the sharpest: Linux puts it under `XDG_RUNTIME_DIR`, not `/tmp`. `deliver.py` already
reads `messagingSocketPath` off the record rather than deriving it, so nothing needs changing — but
anything that ever *does* derive it is broken on two machines out of three. And `procStart` having
three formats means a liveness check comparing it has to branch on `os`, which is a field atlas
already hands over.

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

## Asks of atlas

Four were raised in atlas's own repo. **Three were withdrawn within the hour**, because atlas had
already answered them and the asking was a failure to read its docs first. What that leaves is the
useful part: a boundary, agreed rather than assumed.

**Withdrawn — a machine-readable CLI, and a stable path for the registry.** `shared/CLAUDE.md:14-20`
already names `hosts.json` a registry with three named consumers, and root `CLAUDE.md:24` says
plainly that *atlas-picker reads it directly*. atlas-picker is Rust reading atlas's shared JSON —
the precedent for a non-TypeScript consumer already exists and is documented. A Python daemon doing
the same is the intended pattern, not a workaround. **Deckhand reads `shared/hosts.json`.**

**Withdrawn — `status` on `/api/hosts`.** And the replacement was refused too, correctly:
`~/dev/.atlas-cache-<id>.json` looked like a cheap source of per-host status, and atlas has ruled it
**internal**. The reason is the good one — the main cache carries `shapeVersion` precisely so
atlas-picker can detect a shape change and bail, and `HostFragment` has no such field, so a change
in it would be silent here. **Deckhand reads `shared/hosts.json` and `/api/projects`, and nothing
else of atlas's.**

Ask 4 was also simply wrong on its facts: `~/.atlas/` does not exist on the M2 at all. It exists
only on the remote machines, because that is where the scan agent is `scp`'d.

> One thing came back the other way. On the evidence in these asks, atlas found that `scanHost`
> wrote its fragment with a plain `writeFile` while `readHostFragments` swallows a parse error as
> "that host is simply missing" — so a torn read dropped a whole machine's projects from the merged
> catalog. It now writes temp+rename like the main cache. **That fix is live in the running daemon
> but not yet in git history**, riding with an uncommitted multi-host change in atlas-api. Do not
> pull atlas, fail to find it, and conclude the fragments are still torn.

**Settled — liveness is deckhand's, and it costs nothing.** Atlas sets `status` only in the `catch`
of `scanHost` (`remoteScan.ts:118-128`), on a 10-minute TTL, and a failed scan deliberately keeps
the *previous* `scannedAt` so the catalog can say "ubuntu down, scanned 3h ago". That is a catalog
telling the truth about when it last looked, and the wrong primitive for a dot that says online.

Atlas's answer was better than the probe this plan originally carried: **the link being up is the
machine being up.** The supervised `ssh -L` subprocess already has to exist, and its state is the
reachability signal — no ping, no `lastSeen`, no second SSH round trip, and nothing to keep fresh.
The probe is deleted from this plan rather than moved.

**Settled — who owns persistent remote execution.** Deckhand does. Atlas's only general SSH callers
are `syncAgent(host)` and `scanHost(host)`, both hard-wired to the scan agent with no command
parameter, both behind `$lib`/`$shared` aliases that do not resolve outside atlas-api — and a grep
for `tunnel|forward|ControlMaster|autossh|-L` across the repo returns seven hits, every one a prose
comment. There is no port-forward code in atlas to reuse or to duplicate.

And one offer back. Atlas's project cards already carry `claudeSessions` — `lastAt`, `count`,
`summary` — which is *history*, scraped per project. Deckhand is about to hold the live version for
every machine: which sessions are running right now, where, and busy or idle. That is a loopback
call away whenever atlas wants it.

## Glossary additions

| Term | Meaning |
|---|---|
| **machine** | a computer on the network that runs sessions. The word in the app and in code alike — `host` is already taken by the daemon's own address in `ServerSettings`. |
| **hand** | this daemon in `--hand` mode on a machine that is not this Mac. Reads its own disk, writes one socket, decides nothing. |
