# Installing Deckhand, and pairing a phone or a headset with it

> Status, 2026-10-15. On `feature/pairing` (deckhand, deckhand-web, deckhand-xr): the installer
> and uninstaller, the Mac's id on the beacon and `/health`, and the phone and headset following
> their Mac by that id when its address moves. On `feature/pairing-auth` in all three, waiting
> for JJ: pairing codes and per-device tokens, the phone's Code row, the headset's unpaired
> screen and the web page's code field. That half changes how the daemon authenticates, so it is
> held back until JJ decides. The existing token keeps working on both branches.

## What there is to install

Three servers on the Mac and three clients that reach them.

| Piece | Repo | Port | launchd label | Needs |
|---|---|---|---|---|
| the daemon | `deckhand/daemon` | 4180, all interfaces | `com.jurrejan.deckhand` | uv, iTerm2 with its Python API on |
| deckhand-web | `deckhand-web` | 4132, all interfaces | `com.jurrejan.deckhand-web` | bun |
| deckhand-windows | `deckhand-xr/windows` | 4181, loopback | `com.jurrejan.deckhand-windows` | Swift toolchain, Screen Recording, Accessibility |
| the iPhone app | `deckhand/deckhand` | | | Local Network permission |
| the Quest app | `deckhand-xr/quest` | | | |
| the Mac app | `deckhand/mac` | | | nothing: it reads the token file |

Only the daemon has a token. deckhand-web proxies `/api/*` to the daemon with the cookie
`dh_token` as the header, and deckhand-windows is reachable only from the daemon, on loopback.
So pairing means giving one secret to a client and telling it where the Mac is.

## The audit: what was hardcoded

Measured on 2026-10-15, in `develop` (deckhand, deckhand-web) and `main` (deckhand-xr).

**Where the Mac is**

- `Sources/DeckhandKit/ServerSettings.swift:5`: the iPhone defaults to `m2-2.local`, which is
  JJ's Mac's name. `deckhand/Views/SettingsView.swift:62-65` names it again and offers
  `https://deckhand.jurrejan.com` as the off-network address. That is help text; no code falls
  back to it.
- `Justfile:166`: `just device` launches the phone app on `m2-2.local`, and `:9-10` name the
  simulator and the phone, "Pocketline Swing".
- `deckhand-xr/quest/Justfile:15`: the Quest is told deckhand-web lives at
  `https://deckhand-web.atlas.local.jurrejan.com`. `:51-53` push the daemon as `http://<lan>:4180`,
  which is the IP `/health` reported at that moment. The headset stores that IP and never looks
  again, so a DHCP change or a router swap unpairs it in silence.
- `deckhand-xr/quest/Justfile:9-12`: `fractal`, the Quest's adb serial and `C:/dev/_rig_tmp`. Pairing
  goes over ssh to the PC the headset's USB cable is in.
- The NAS Caddy site `deckhand.caddy` reverse-proxies to the literal `192.168.178.180:4180` and
  checks the literal token. Both values live outside every repo.
- `deckhand-web/svelte.config.js:10` trusts `https://deckhand-web.atlas.local.jurrejan.com`, and
  its plist sets `ORIGIN=https://deckhand-web.jurrejan.com`.

**Paths and the user**

- `launchd/com.jurrejan.deckhand.plist:9-28`: `/opt/homebrew/bin/uv`, `/Users/jurrejan/...` four
  times, and the main checkout as working directory. `install-agent` symlinked this literal file.
  On any other Mac, or from a worktree, it ran the wrong code or none at all.
- `deckhand-web/launchd/com.jurrejan.deckhand-web.plist:9-33`: `/Users/jurrejan/.bun/bin/bun`,
  the checkout, the logs and `HOME`.
- `deckhand-xr/windows/launchd/com.jurrejan.deckhand-windows.plist:11-21`: the main checkout's
  binary and the logs, both under `/Users/jurrejan`.
- `mac/Desk.swift:220-223`: the token is read from `~/Library/Application Support/Deckhand/token`
  on loopback. That is correct for the Mac itself, so it stays.

**Ports.** 4180 appears in `config.py:12`, `ServerSettings.swift:6`, the Quest Justfile and
deckhand-web's fallback. 4181 appears in `windows/…/main.swift:5` and `space/windows.py:25`, and
4132 in the web plist. They stay as defaults, because a port nobody has to choose is part of
installing being easy. What changes is that no client has to know the address they are on.

**The token.** It is typed on the phone (`SettingsView.swift:74`), stored in plain
`UserDefaults`, pushed to the Quest as an adb intent extra (`Pairing.kt:41-55`), pasted into
deckhand-web's `/pair` page, and written literally into the NAS Caddy file. One secret in five
places, and none of them can be revoked without revoking all of them.

**Kept on purpose, because they are identity rather than configuration:** the bundle ids
`dev.jurrejan.*`, team `KA6433FU8U`, the APNs topic, the launchd labels `com.jurrejan.*`, the
1Password item `deckhand`, and the `install.jurrejan.com` over-the-air page. Someone forking the
project changes these once, in `project.yml` and the plist templates. A user never sees them.

## Installing

**One command on the Mac: `just setup`, run from the deckhand checkout.** It does the following,
in order, and is safe to run again.

1. It checks for what it cannot install for you: uv always, bun and a Swift toolchain when it
   finds deckhand-web or deckhand-xr. For each one missing, it names the command to install it
   and stops. A missing `claude` is a note, not a stop.
2. `uv sync` for the daemon.
3. It writes the Mac's two optional addresses, if they are given: `web_url=` (where deckhand-web
   answers) and `remote_url=` (the off-network URL). Each is a one-line file in the data folder, the
   way `token` is. The daemon publishes them on `/health`, so a client learns them from the Mac
   it found rather than from a constant.
4. It renders each launchd plist from its template, with this Mac's home, the path to this
   checkout, `uv` and `bun` filled in. It writes the result into `~/Library/LaunchAgents` and
   loads it, unless the job is already loaded. A loaded job is never restarted by setup. Use
   `just restart` for that, so re-running setup can never bounce a daemon a phone is using.
5. deckhand-web and deckhand-windows are installed the same way, through their own repos' own
   `install-agent`, when it finds their checkouts. By default it looks beside this one;
   `web_dir=<folder>`/`xr_dir=<folder>` (or `DECKHAND_WEB_DIR`/`DECKHAND_XR_DIR`) point it elsewhere. A
   missing one is skipped with a sentence, never treated as a failure: the phone needs only the
   daemon.
6. For deckhand-windows it says why it wants each permission before macOS asks. Then it opens the
   two Privacy panes and waits until `/health` on :4181 reports both granted.
   - Screen Recording: "so your headset can show a Mac window. Frames go to the headset and
     nowhere else; nothing is saved."
   - Accessibility: "so pointing at that window in the headset can click it, with this Mac's own
     cursor."

   It also names iTerm2's Python API (Settings › General › Magic), because the daemon finds
   panes through it.
7. It ends with the one next step: open the app on the phone or headset, and pair.

**`just teardown` undoes it.** It boots out and removes all three agents, the `deckhand` CLI, the
MCP entry and the skill link. It leaves `~/Library/Application Support/Deckhand` in place, because
that folder holds the token every paired device uses. It prints the path, and `rm -rf` of that
folder is the rest of a clean uninstall.

**Why render instead of symlink.** A plist cannot say "this user's home" or "this checkout":
launchd expands nothing. A symlinked literal file is therefore always one Mac's file. The
template is tracked, and the rendered plist is the Mac's own copy in `~/Library/LaunchAgents`.
That breaks the `~/dev` rule that a plist is symlinked from the repo, and the rule needs a line for
this case. **For JJ:** `daemons.json` gets a `com.jurrejan.deckhand-windows` row, which is missing
today. Each row's `plist` field should point at `~/Library/LaunchAgents/<label>.plist`. That is an
atlas edit and is not made from here.

**Migration on JJ's Mac.** The literal plists stay tracked on `feature/pairing`, so merging it
breaks no symlink. The first `just setup` replaces each symlink with a rendered file; for the
current values the rendered file is identical to the literal one, apart from paths that are now
worked out. After that the literal files are dead and the follow-up commit removes them.

## Being found, and following the Mac when its address moves

Bonjour already answers *where*. What it did not answer is *which Mac*. A client that stored an
IP had no way to tell "my Mac moved" from "a different Mac is here", so it could not safely
re-find its own.

- **The Mac has an id.** It is twelve hex characters, made once and kept as the file `id` in the
  data folder. It goes out on the beacon as `id=` and on `/health` as `id`. It is not a secret:
  it names a Mac and grants nothing.
- **A client stores the id beside the address**, read from `/health` the first time a check
  succeeds. When the stored address stops answering, the client browses `_deckhand._tcp`, takes
  the beacon with the same id, checks `/health` on it and stores the new address. A beacon with a
  different id is never adopted on its own. A phone in a house with two Macs must not switch
  between them silently, which is the rule `ServerSettings.adopts` already enforces.
- **deckhand-web's address comes from the Mac** (`/health.web`), not from the client. The headset
  used to be handed a hostname at pairing time and kept it. Now it asks the Mac it found every
  time it pairs or re-finds. It should be a name the headset can resolve: Android does not
  resolve `.local`.
- **The `.local` name stays preferred on the phone** (`Beacon.answering`), and the Quest uses
  the `lan` IP the beacon carries. On the phone this is `ServerSettings.adopts(kept:heard:)`; on
  the headset `Refind.kt`. Either way, an address is something re-found, never something
  typed.

This covers the IP and DNS drift case. The Quest held `http://192.168.178.x:4180`, which
`just quest::pair` had pushed, plus an `atlas.local` hostname that depends on wildcard DNS and
hairpin NAT staying put. When either one moved, nothing on the headset could recover. With an id
and a browse, the daemon half heals itself. The web half heals as far as the Mac's own `web`
setting is right, because that is a single value on the Mac and not one copy on every device.

## Pairing

**Recommendation: the Mac shows a six-digit code and the client types it.** The Mac opens a
pairing window when the person at it asks for one. Nothing else opens it.

1. The client browses and lists the Macs it hears. With one Mac it goes straight on.
2. On the Mac, the person runs `just pair` (or the **Pair a device** button on
   Deckhand's page in utt). The Mac shows a code such as `482 913`, valid for five minutes.
3. The person types it on the phone or in the headset. The client sends `POST /pair` with the
   code, its own name and its kind. The Mac answers with a token minted for that device alone,
   and closes the window.

**Why a code typed on the client, and not approval on the Mac.** Approval on the Mac lets
anything on the LAN start a pairing: every request puts a dialog on the Mac, and the person learns
to click it away, which is exactly the habit an attacker needs. With the code, the window is
opened from the Mac, by someone who already holds the Mac's token (the CLI and utt read the token
file). Until then, `POST /pair` answers 410 to everyone. Reading a code off the Mac's screen is
the same physical-presence proof a confirmation click would be, with no dialog to spam.
Numeric comparison (a code shown on both sides) protects against an active man in the middle,
but this LAN carries plain HTTP. Anyone who can intercept the pairing can read the token on any
later request, so comparison would add a step and no protection.

**The window's rules:**

- six digits from `secrets`; five minutes; single use. The window closes on success.
- five wrong codes close the window. To guess, an attacker gets five tries at one in a million
  per window the person opens, and that person is standing at the Mac at the time.
- `POST /pair` is limited to twenty requests a minute in total, so a flood costs a 429 and a log
  line. It does not cost a CPU.
- The code never travels on the beacon or on `/health`. Opening a window needs the Mac's own
  token, so a paired phone cannot open one for someone else.
- A refusal says which of three things went wrong: 403 for a wrong code, 410 for no window open,
  and 429 for too many requests. These carry no information an attacker can use, and a person
  who mistyped needs to know.

**On the headset**, the unpaired launcher lists the Macs it hears. Picking one shows a digit field
and a line saying where the code is. There is no adb, no `fractal` and no cable. `just quest::pair`
remains for development and for a daemon that predates pairing codes.

**On the phone**, the Mac section of Settings shows the Macs it hears. Picking one fills the
address, and a Code field pairs. The Token field stays available, because the Mac's own token
still works everywhere, for example to pair from outside the house.

**Re-pairing after the IP changes** needs nothing from the person: see "Following the Mac" above.
**Pairing from outside the home network** is not possible by code, and should not be. The window
is meant to be reachable only by someone in the same room as the Mac. The person pairs at home
once, and the token then works through the off-network URL, which the Mac publishes as
`/health.remote` so that the phone can offer it rather than ask for it to be typed. The one
exception is the Caddy note below.

## Security: one shared token, or a token per device

**Today** there is one token, 72 bits, made with `token_urlsafe(9)` so it is short enough to type.
The daemon, every hand, the phone, the headset, deckhand-web's cookie and the NAS Caddy all hold
it. It is the only thing in front of a daemon that can type into Claude sessions.

**Recommended: one token per device, with the Mac's own token kept for the Mac.**

- **For:** a lost phone is revoked with `just forget <device>`, and nothing else has to
  re-pair. A token read off the headset (SharedPreferences, adb backup) is that headset's token
  and no one else's. The daemon can say which device made a request, so `presence` and the log
  stop guessing. A device token no longer has to be typable, so it is 192 bits.
- **Against:**
  - There is more state: `devices.json`, holding SHA-256 hashes and never the tokens themselves.
  - There is one more comparison per request.
  - **The NAS Caddy checks the literal shared token.** A device token is refused off the home
    network until that site file stops comparing a literal and forwards the check to the daemon
    (`forward_auth` to `GET /pair/check`, which answers 200 or 401 and is cheap to call).
- **What does not change:**
  - The Mac's own token stays in the token file, and `require_token` still accepts it. The CLI,
    MCP server, utt page, Mac app and every hand go on using it unchanged.
  - Existing phone and headset pairings hold that token, so they go on working. Nobody is locked
    out by the change.
  - Once every device has re-paired by code, rotate the Mac's token (delete the file and restart).
    That retires every copy of the old one, including the adb extras and the NAS file.
- **Per-device tokens do not fix plaintext on the LAN.** Anything that can sniff the Wi-Fi reads
  a token off any request, as it can today. TLS on the LAN is the fix for that. Every LAN client
  would have to trust a local certificate, which makes it its own decision, and it is out of
  scope here.

**The routes it adds** (all on `feature/pairing-auth`):

| Route | Token | Answers |
|---|---|---|
| `POST /pair/open` | the Mac's own | `{code, expires, seconds}`: opens or replaces the window |
| `POST /pair` | none | `{token, device, mac}`; 403 wrong code, 410 no window, 429 too many |
| `GET /pair/check` | any | 200 or 401: for Caddy's `forward_auth` |
| `GET /devices` | the Mac's own | every paired device: id, name, kind, paired, last seen |
| `DELETE /devices/{id}` | the Mac's own | 204: that device's token stops working at once |
| `POST /pair/transcribe` | the Mac's own | `{token, device}`: a token scoped to `/transcribe` |

**A token for one route.** `just transcribe-token name=<page>` mints a device row with
`scope: transcribe` and puts its token on the clipboard, never on the screen. That token passes
`pairing.allows_transcribe` and nothing else: every other route, `/pair/check` included, answers
it 401. It is the token a web page keeps in localStorage for its mic button (the Jaimes chat in
wallgen's web UI), where any script on that page can read it, so it can turn audio into text and
cannot speak into a session. `just forget <id>` revokes it like any device. The page reaches
`/health` and `/transcribe` through CORS for two origins only (`browser/`).

## Decisions for JJ

1. **Merge `feature/pairing-auth`**, in deckhand and deckhand-xr, and in deckhand-web for its
   `/pair` page. It changes `require_token`. Nothing that works today stops working.
2. **The NAS Caddy:** replace the literal token check in `deckhand.caddy` with
   `forward_auth 192.168.178.180:4180 { uri /pair/check }`, so device tokens work off the home
   network too. Until then, off-network use needs the Mac's token.
3. **Rotate the Mac's token** once every device has paired by code.
4. **The `~/dev` rule on plists** ("symlinked from `~/Library/LaunchAgents`") needs an exception
   for rendered ones, and `daemons.json` needs the deckhand-windows row.

## How to try it

1. After merging `feature/pairing`, from the deckhand main checkout: `just setup
   web_url=https://deckhand-web.atlas.local.jurrejan.com remote_url=https://deckhand.jurrejan.com
   web_dir=~/dev/web/deckhand-web`. The daemon is already loaded, so setup writes the two files
   and leaves it running. `just restart-agent` loads the new code; then
   `curl -s localhost:4180/health` shows `id`, `web` and `remote`.
2. With `feature/pairing-auth` merged and the daemon restarted: `just pair` prints a code. On the
   phone: Settings › Mac › pick the Mac › Code. In the headset: open Deckhand unpaired, pick the
   Mac, type the code. In a browser: deckhand-web's `/pair` takes the six digits.
3. `just devices` lists what is paired; `just forget <id>` revokes one device.
