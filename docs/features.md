# Deckhand — feature catalogue

Code-verified against `develop` @ `0103784`. Every line cites `file:line`, repo-relative.
Daemon paths abbreviate `daemon/src/deckhand_daemon/` as **`D/`**.

Sibling documents: [../CHANGELOG.md](../CHANGELOG.md) is what landed, [history.md](history.md)
is how it was asked for. This one supersedes the capability index at
`.orchestrate/capabilities.md`, whose fourteen errors are listed in §18.

Vocabulary is GLOSSARY.md's: session, pane, record, transcript, listing, turn, inbox, briefing,
ask, clip, hint, route, filter, chain, verdict, slip (to a person) / artifact (in code), page,
file, snap, markup, spot, surface, rail, deck, mark, glyph, state word, tint, accent.

---

## 1. Daemon — the HTTP surface

Every route below except `GET /health` requires the `x-deckhand-token` header, applied per
decorator or via the five router mounts (`D/app.py:52-56`). A dead `session_id` is 404
everywhere (`D/saying.py:41`). A bad query/body is 422 (FastAPI).

### 1.1 Sessions and the Mac

| Method · path | Params / body | Response | Cite |
|---|---|---|---|
| `GET /health` | — (no token) | `name, version, host, lan, iterm` | `D/app.py:59` |
| `GET /sessions` | — | `sessions[]` (record + `last_request` + `context{used,limit}` + `model` + `effort` + `artifacts_waiting` + `artifacts_answered`), `iterm`, `week` | `D/app.py:77` |
| `GET /sessions/{id}/summary` | — | briefing off disk: `summary, headline, tasks[], spent{runs,tokens,cached}, error, writtenAt, stale`; bumps this session to the front of the briefing queue | `D/app.py:107`, `D/briefings.py:72` |
| `GET /briefings` | — | `briefings{sid: <summary>}` — every live session at once, no model run | `D/app.py:120` |
| `GET /sessions/{id}/turns` | `limit` 1–200 (**default 8**), `before` ≥0 | `turns[], queued[], more`; `queued` only on page 0 | `D/app.py:165` |
| `GET /sessions/{id}/raw` | `limit` 1–4000 (default 1500) | `lines[]` — readable JSONL, for when the app's reading looks wrong | `D/app.py:203` |
| `GET /sessions/{id}/context` | — | `documents[], tokens` — every CLAUDE.md the folder loads, connectors pre-drawn | `D/app.py:190` |
| `GET /sessions/{id}/commands` | — | `commands[]` — slash commands and skills this session could be handed | `D/app.py:229` |
| `POST /sessions/{id}/queue/clear` | — | `cleared` — draws a line under the inbox; transcript untouched | `D/app.py:214` |
| `POST /sessions/{id}/focus` | — | `focused`; 409 when there is no pane | `D/app.py:221` |
| `POST /sessions/{id}/control` | `action` ∈ `cancel\|compact\|clear\|exit` | `sent`; 400 unknown, 409 no pane | `D/app.py:243`, `D/deliver.py:46` |
| `POST /sessions/{id}/name` | `{name}` | `renamed, was, carried_filters` — types Claude Code's own `/rename` into the pane, carries the chain | `D/app.py:264`, `D/filters/config.py:51` |
| `POST /live/token` | `{token, kind}`, kind ∈ `activity\|start` | `registered`; 400 on any other kind | `D/app.py:277` |
| `POST /sessions/{id}/notify` | `{line}` | `pushed` (+`why` when a folder refuses); 400 on blank | `D/app.py:297` |

### 1.2 Speaking into a session

| Method · path | Params / body | Response | Cite |
|---|---|---|---|
| `POST /sessions/{id}/audio` | `route`, `deliver` (default true); multipart `file` ≤32 MB, suffix in `AUDIO_SUFFIXES` | **201** with `path, bytes, received_at, transcript, transcript_error, prepared, delivered, delivered_by, delivery_error, notes, stopped_by`; 400 empty, 413, 415 | `D/saying.py:58`, `:31` |
| `POST /sessions/{id}/say` | `route`, `prepared`; `{text, images?}` | `delivered, delivered_by, delivery_error, notes, stopped_by` | `D/saying.py:155` |
| `POST /sessions/{id}/image` | multipart `file`, image types, ≤32 MB | `{path}` under this session's own `images/<id>/` | `D/saying.py:133` |
| routes as authority | `auto` / `keyboard` (`it2 session send`, as the person) / `socket` (peer frame, labelled as another agent, `PREAMBLE` prefix) — `keyboard` never silently falls back | | `D/deliver.py:37`, `D/saying.py:89` |
| `Delivery.went` | `delivered && stopped_by is None` — a filter can stop a prompt the daemon accepted | | `D/filters/kinds.py:49-65` |

### 1.3 Slips (artifacts)

| Method · path | Params / body | Response | Cite |
|---|---|---|---|
| `GET /sessions/{id}/artifacts` | — | `artifacts[]{id,title,modified,answered}`, newest first | `D/artifacts.py:258` |
| `GET /sessions/{id}/artifacts/{aid}` | — | the page as `text/html`; 404 past a size ceiling | `D/artifacts.py:265` |
| `GET /sessions/{id}/artifacts/{aid}/answer` | — | `{value}`; `null` means nobody has answered | `D/artifacts.py:275` |
| `POST /sessions/{id}/artifacts/{aid}/answer` | `route`; `{value}` required, **cannot be `null`** | `answer{id,answeredAt,value,file}, delivered, delivered_by, delivery_error`; file written before the session is messaged | `D/artifacts.py:289` |
| store | `<cwd>/.deckhand/artifacts/<slug>.html` + `<slug>.answer.json`; `.deckhand/.gitignore` (`*`) seeded on first read; traversal and symlink escapes refused | | `D/artifacts.py:172`, `:154-174`, `:57-74` |

### 1.4 Files

| Method · path | Params | Response | Cite |
|---|---|---|---|
| `GET /sessions/{id}/files` | — | `files[]{path,name,kind,size,modified}` — only what the transcript named | `D/app.py:134` |
| `GET /sessions/{id}/file` | `path` (required) | `FileResponse`; 404 if the listing never named it, 413 over `MAX_FILE_BYTES` 512 MB | `D/app.py:141`, `D/config.py:15` |
| second door | the CLAUDE.md context tree also grants a path (`context.allowed`) | | `D/reading/context.py:68`, `D/app.py:156` |

### 1.5 Filters, projects, settings

| Method · path | Params / body | Response | Cite |
|---|---|---|---|
| `GET /filters` | — | `{known:[{name,title,summary,fields}]}` — global, static | `D/filters/routes.py:30` |
| `GET /sessions/{id}/filters` | — | `{session: name, known, steps}` | `D/filters/routes.py:36` |
| `PUT /sessions/{id}/filters` | `{steps:[{filter,on?,settings?}]}` | `{session, steps}` as stored; **400 on any unknown filter name**, nothing partially saved | `D/filters/routes.py:43`, `:51-54` |
| `GET /projects` | — | `{projects:[16 fields], source}` — `file`/`atlas`/`atlas-cache`/`none`; rows carry `live` and `trusted` | `D/projects/routes.py:26`, `:37-43` |
| `POST /projects/session` | `{path}` | `{session: <full row, pane included>}`; **400** not in the catalogue, 409 could-not-start with a reason | `D/projects/routes.py:47` |
| `GET /settings` | — | 7 global keys + `projects` override map + `offers` | `D/settings/routes.py:19` |
| `PUT /settings` | bare dict | what was **stored**, read back; unknown keys dropped, unoffered model refused, an empty override deleted — never 400 | `D/settings/routes.py:24`, `D/settings/wants.py:99-120` |
| `GET /settings/project?path=` | `path` | `{path, wants{7 resolved keys}}` — keyed by **path**, not session id | `D/settings/routes.py:30` |

---

## 2. Daemon — background jobs

All four start in the lifespan and are cancelled on shutdown (`D/app.py:39-48`).

| Job | Trigger / gates | Writes | Cite |
|---|---|---|---|
| Briefing writer | loop `GAP=4 s`, `IDLE=15 s`; woken early by `bump`; two gates — transcript `st_mtime`, then sha256 of `asks + activity` | `briefings/<sid>.json` `{summary, headline, hash, mtime, written_at, error}` | `D/briefings.py:88-100`, `:36,39`, `:145-170` |
| Briefing model run | Haiku 4.5 from `prompts/briefing.md` frontmatter (per-folder `summary_model` override), thinking disabled, `max_turns 16`, timeout 60, `tools=[]`, exactly three task tools | `tasks/<sid>.json` via the SDK tools | `D/summarize.py:133-150`, `:109-117`, `D/tasks.py:153` |
| Idle check (nudge) | loop `POLL=30 s`; `SETTLE=120 s` quiet, `AGAIN=30 min` cooldown; asked again only when an ask it was not already asked about is open (ids, never states); per-folder `chase`; `DECKHAND_NUDGE=0` kills it Mac-wide | `nudged.json` (what each session was last asked about, so a restart does not ask again); sends `prompts/idle-check.md` on the **socket** route | `D/nudge.py:53-63`, `:29,32,35`, `:48`, `:76`, `:126` |
| APNs sweep | loop `POLL=5 s` | no disk; HTTP/2 POSTs to APNs | `D/push.py:181-188`, `:170` |
| utt plugin install | once at startup, rewrites the manifest every start | `deckhand.json` + `deckhand.status.json` | `D/app.py:43`, `D/plugin.py:142-151` |
| utt plugin watch | loop `POLL=1.0 s`; values applied on `revision` change, actions on a strictly increasing `sequence` | mutates `deliver.PREAMBLE`, runs pbcopy / `open -a Console` | `D/plugin.py:154-163`, `:181-214` |

---

## 3. Daemon — state on disk

Root `~/Library/Application Support/Deckhand/`, overridable by `DECKHAND_DATA_DIR` (`D/config.py:19`).

| Path | Owner | Cite |
|---|---|---|
| `token` (0600) | `config` | `D/config.py:44-54` |
| `audio/<sid>/<utcstamp>-<hex8><suffix>` | `saying` | `D/config.py:27`, `D/saying.py:79` |
| `images/<sid>/<epoch>-<hex8><suffix>` | `saying` | `D/config.py:33`, `D/saying.py:149` |
| `briefings/<sid>.json` | `briefings` | `D/briefings.py:42-57` |
| `tasks/<sid>.json` — the ask list, `MAX_KEPT=200`, `MAX_TEXT=120`, states todo/doing/done | `tasks` | `D/tasks.py:24-35`, `:184` |
| `queue/<sid>.json` — the inbox line drawn by `/queue/clear` | `reading/asked` | `D/reading/asked.py:137` |
| `push-tokens.json` (0600) `{activity, start}` | `push` | `D/push.py:52-63` |
| `apns.p8`, `apns-key-id` | `push` (written by `just sync-apns`) | `D/push.py:79-84`, `Justfile:37` |
| `projects.json`, `filters.json`, `settings.json` | `projects/sources`, `filters/config`, `settings/wants` | `D/projects/sources.py:145`, `D/filters/config.py:30`, `D/settings/wants.py:77` |
| `~/Library/Logs/Deckhand/deckhand.log` + `launchd.{out,err}.log` | `log` / launchd | `D/log.py:14`, `launchd/com.jurrejan.deckhand.plist:20,22` |
| project-local `.deckhand/artifacts/*.html`, `*.answer.json`, `.gitignore` | `artifacts` | `D/artifacts.py:154-174` |

---

## 4. Daemon — auth, process, launchd

| Feature | Detail | Cite |
|---|---|---|
| Pairing token minted | `secrets.token_urlsafe(9)` → 12 chars, `chmod 0600` | `D/config.py:51-53` |
| Checked per request | `require_token` header compare (plain `!=`), 401 `bad token`; re-read from disk every request | `D/app.py:34-36`, `D/config.py:44-49` |
| Only open route | `GET /health`, so the app can tell "wrong host" from "wrong token" | `D/app.py:59-61` |
| Server | uvicorn, `0.0.0.0:4180`, entry point `deckhand_daemon.app:main` | `D/app.py:290-294`, `D/config.py:10` |
| launchd agent | label `com.jurrejan.deckhand`, `uv run deckhand-daemon`, `RunAtLoad`+`KeepAlive` true, `ProcessType Interactive` (iTerm timeouts) | `launchd/com.jurrejan.deckhand.plist:6,9-11,16,18,30` |
| Install / remove | symlink into `~/Library/LaunchAgents` + bootstrap, then poll `/health` | `Justfile:222-230` |

---

## 5. Daemon — reading (`D/reading/`)

| Feature | Caps and rules | Cite |
|---|---|---|
| Find a session's transcript | id matched `[A-Za-z0-9_-]{6,64}`, then glob `~/.claude/projects/*/<id>.jsonl`, newest mtime wins; `DECKHAND_CLAUDE_HOME` overrides | `D/reading/transcripts.py:74-80`, `:70` |
| Tail-only reads | `TAIL_WINDOWS = (512 KB, 4 MB, 32 MB)`; first line of a partial read dropped as a fragment | `D/reading/transcripts.py:18`, `:218-225` |
| Turn parsing | `MAX_TEXT=4000` per message; the wrappers opened by `machinery`, then non-printables stripped | `D/reading/transcripts.py:83-107` |
| Machine wrappers | a known-names list, never a shape: `NOISE` dropped whole, `PEER` folded to a `**From <who>:** <summary>` label over the body, `task-notification` down to its summary and result, an `idle_notification` frame down to its `result`; fences sacred to everything and backticked spans sacred to the tag stripping; an unclosed tag loses the tag and keeps the words | `D/reading/machinery.py:78`, `:96`, `:104` |
| Tool dots under a turn | one shown input at `MAX_DETAIL=140` (preference `command,file_path,pattern,path,description,prompt,url,query`), full call/result at `MAX_FULL=4000`, matched by `tool_use_id` | `D/reading/transcripts.py:29-35`, `:299-372` |
| Thinking | collected like tools; `redacted_thinking` deliberately skipped | `D/reading/transcripts.py:237-252` |
| A message absorbed mid-turn is a turn | `attachment/queued_command` read as an ordinary user turn, no tools hung on it | `D/reading/transcripts.py:124-141` |
| Paging backwards | `page_turns(limit, before)` counts from the end, widens the window until it has enough, returns `more` | `D/reading/transcripts.py:189-215` |
| Live in-flight turn | trailing tools/thoughts become a turn with empty text | `D/reading/transcripts.py:293` |
| Activity blob for a briefing | cap 12 000 chars, 4 MB window, resets at each user turn | `D/reading/transcripts.py:144-181` |
| Context fullness + model + effort | `last_request` sums input + cache-creation + cache-read tokens, `USAGE_WINDOW=256 KB`; `context_window` from `autoCompactWindow`, `DEFAULT_WINDOW=200 000` | `D/sessions.py:234-279` |
| Ask list off the transcript | `MAX_ASK=600`, `MAX_TRACE=10` trailing work lines, cap 8 000; still-queued items appended as "not picked up yet" | `D/reading/asked.py:32-64` |
| Inbox replay | replays `queue-operation` `enqueue/dequeue/remove/popAll`; a leave naming nothing pops the oldest | `D/reading/asked.py:67-108` |
| Draw a line under the inbox | writes `{"cleared": <ISO ms Z>}`; replay skips ops at or before that stamp | `D/reading/asked.py:111-138` |
| Readable raw lines | `MAX_LINE=1200`, `MAX_LINES=1500`; `DULL` skips 9 entry types (incl. `attachment`, unless it is an absorbed message) | `D/reading/readable.py:29-74` |
| CLAUDE.md context tree | `MAX_DOCS=80`, `MAX_DEPTH=6`, skips `.git node_modules .venv __pycache__ .build DerivedData _archive` + dotdirs, one walk total; tokens = bytes / 2.5 (atlas's estimate) | `D/reading/context.py:27-35`, `:101-139` |
| Tree order and connectors | ancestors under `$HOME` → `~/.claude/CLAUDE.md` → project → descendants → `GLOSSARY.md` → `.claude/rules/*.md`; `│   ├── ` drawn server-side | `D/reading/context.py:82-98`, `:142-177` |
| Slash commands + skills | project `.claude` shadows `~/.claude`; `commands/git/amend.md` → `git:amend`; a skill's frontmatter `name` beats its folder; `PEEK=4096` bytes of frontmatter only; commands sorted before skills | `D/reading/commands.py:30-33`, `:57-116` |
| Session join | `~/.claude/sessions/<pid>.json` counts only while `ps` shows the pid; `ps` gives the tty, `it2 session list --json` maps tty → pane; pane cache 3 s | `D/sessions.py`, `D/projects/starting.py:182-196` |

---

## 6. Daemon — projects (`D/projects/`)

| Feature | Detail | Cite |
|---|---|---|
| Source order, first non-empty wins | `<data>/projects.json` → atlas HTTP `127.0.0.1:47891/api/projects` (3 s) → `~/dev/.atlas-cache.json` (`DECKHAND_ATLAS_CACHE`) | `D/projects/sources.py:114-133`, `:143-173` |
| Cache | 60 s, matching atlas's own TTL; sorted by `touched_at` desc; `forget()` drops it | `D/projects/sources.py:41`, `:128-140` |
| Row filtering | atlas rows keep only `isLocal is True`; anything archived or under `/_archive/` dropped | `D/projects/sources.py:176-203` |
| Row shape | 16 fields — `name, path, relative, description, kind, touched_at, live, trusted, framework, runner, branch, dirty, issues, port, domains, sessions` | `D/projects/sources.py:46-111` |
| Trust check | `~/.claude.json` `hasTrustDialogAccepted`, read fresh; any parse failure refuses everything | `D/projects/starting.py:84-98` |
| Start a session | refuses an untrusted folder **before** opening anything; `it2 window new` (never `tab new`); polls the new pane `OPENING=6 s` | `D/projects/starting.py:101-130`, `:145-160` |
| Launch line | `cd <folder> && claude --name <free> [--model opus\|sonnet\|haiku] --dangerously-skip-permissions --chrome` — `--name` mandatory because bare `claude` opens the dashboard | `D/projects/starting.py:80`, `:22-26`, `:120-123` |
| Name collisions numbered `-2…-99` | name is the key for stars, hidden and filter chains | `D/projects/starting.py:133-142` |
| Waits for the real session | polls `live_sessions` every `POLL=0.5 s` up to `SETTLE=40 s` for a matching resolved cwd, then busts the pane cache so the receipt is never `pane: null` | `D/projects/starting.py:163-196` |

---

## 7. Daemon — settings (`D/settings/wants.py`)

| Key | Type | Default | Consumer | Cite |
|---|---|---|---|---|
| `finished` | bool | true | session stopped → Lock Screen card | `:49`, `D/push.py:204` |
| `slips` | bool | true | a new unanswered slip → card | `:51`, `D/push.py:238` |
| `called` | bool | true | gates `POST /notify` | `:53`, `D/push.py:253` |
| `chase` | bool | true | gates the idle check | `:55`, `D/nudge.py:75` |
| `subagents` | bool | **false** | **none — see §17** | `:58` |
| `session_model` | str | `""` | `--model` flag when starting a session here | `:60`, `D/projects/starting.py:122` |
| `summary_model` | str | `""` | the briefing summariser's model | `:62`, `D/summarize.py:117` |

- Offers: `SESSION_MODELS = opus/sonnet/haiku` (aliases, the CLI resolves them); `SUMMARY_MODELS = claude-haiku-4-5-20251001 / claude-sonnet-5 / claude-opus-5` (full ids, the SDK no-ops on an alias) — `D/settings/wants.py:35-41`.
- Merge is **per key, not per object**: a folder that overrode only `summary_model` keeps following every other global switch as it changes — `D/settings/wants.py:123-135`.
- `None` on the wire is the stored form of "no opinion" and is preserved in the document; only `resolved` turns it into an answer — `D/settings/wants.py:156-178`.
- A model outside its offer list is refused → `None` → falls back; `""` is a real answer meaning "the default" — `D/settings/wants.py:185-197`.

---

## 8. Filters — the prompt chain (`D/filters/`)

| Filter | Wire name | What it does | Settings | Cite |
|---|---|---|---|---|
| Word replacement | `words` | whole-word, case-insensitive swap, replacement taken as typed; `(?<!\w)…(?!\w)` guards so punctuation-ending pairs are safe; malformed pairs skipped silently | `pairs` (kind `pairs`, default `()`) | `D/filters/words.py:47-63`, `:20`, `:37` |
| Prompt crafting | `craft` | rewrites dictation into a structured prompt via the prompt-crafter skill on a one-tool Agent SDK run; **async**, **not idempotent** | `target` (text, `opus-5`), `floor` (number, 12) | `D/filters/crafting.py:109-132`, `:16-18` |

- Contract types: `Prompt{text, session_id, session_name, cwd, route, images, source}`, `Verdict{text, note, stop}`, `Outcome{text, notes, stopped_by, reason}`, `Field{key,label,kind∈text|bool|number|pairs,default,hint}`, `Filter{name,title,summary,fields,apply}` — `D/filters/kinds.py:19-99`.
- Chain storage: `filters.json` `{"chains": {<session NAME>: [step]}}` — keyed by **name** because an id dies on restart; renaming carries the chain over — `D/filters/config.py:29-30`, `:51-67`.
- Array order **is** run order; the same filter may appear twice; a step is a position, not a key — `D/filters/config.py:3-5`, `:119-129`.
- Empty chain removes the key rather than storing `[]`; an unreadable file loads empty and logs — `D/filters/config.py:44-46`, `:70-91`.
- Legacy Mac-wide `{"steps": …}` is retired, not migrated: logged whole and renamed `filters.global.json` — `D/filters/config.py:94-112`.
- Runner: `on:false` skipped; unknown filter noted and stepped over; each step gets the previous step's text; `stop` sets `stopped_by` + reason and breaks; a raising filter is logged, noted and skipped — words carry on unchanged — `D/filters/runner.py:20-67`.
- Every `craft` failure is a note plus unchanged text: skill missing, SDK absent, model error, timeout (shielded), `ClaudeSDKError`/`OSError` — `D/filters/crafting.py:41`, `:69`, `:93`, `:102`, `:105`.
- The chain runs once on `?deliver=false` too, so the review card shows what will really be sent (`prepared`) — hence `/say?prepared=true` — `D/saying.py:53`.

---

## 9. Prompts (`D/prompts/`)

| File | For | Placeholders | Frontmatter read | Caller |
|---|---|---|---|---|
| `briefing.md` | the briefing agent: status line, 15-line update, three task tools | none | `model, thinking, max_turns, timeout, ask, tools` | `D/summarize.py:17-21`, `:105`, `:138` |
| `crafting.md` | the `craft` filter's agent | `{skill} {target} {cwd} {name}` | `model, effort, max_turns, timeout, allowed_tools, skill` | `D/filters/crafting.py:31-36`, `:74-86` |
| `idle-check.md` | the message a quiet session is **sent** (not a model run) | `{name}` ×4, `{listed}` | `route: socket` | `D/nudge.py:37`, `:89-90` |

- Loader: `load(name)` reads `<name>.md` beside the module; the file must open `---\n` and close `\n---\n` or it raises at import — `D/prompts/__init__.py:50-67`.
- `.filled(**values)` is a literal `str.replace` of `{key}`, never `str.format`, so a brace in an edited prompt cannot raise; an unreplaced placeholder passes through silently — `D/prompts/__init__.py:36-47`.
- Prompts are read once at import: editing one needs a daemon restart — `D/prompts/CLAUDE.md:19-21`.
- Everything the daemon says to a model is a file here, never a Python string (global invariant).

---

## 10. Transcription — the utt file lane (`D/transcribe.py`)

| Feature | Detail | Cite |
|---|---|---|
| No listener, no token, nothing on the network | clip copied into utt's plugin jobs folder, utt writes the text beside it | `D/transcribe.py:44-66` |
| Write-then-rename | clip lands as `<name>.wav.part` and is renamed, or utt reads mid-write | `D/transcribe.py:44-66` |
| Hints before the rename | `<name>.hints.json` must exist first or utt has already passed it by; `hints_for` seeds vocabulary per session and folder | `D/transcribe.py:82-88` |
| Unsupported suffix | returns `utt cannot open .<ext> files` rather than hanging | `D/transcribe.py:32-33` |
| Cleanup | the utt-side job copy is the only thing the daemon ever unlinks | `D/transcribe.py:86` |
| Off switch | `plugin.turned_off` (a `deckhand.disabled` file) short-circuits transcription | `D/transcribe.py:42`, `D/plugin.py:57-68` |

---

## 11. Push and the Live Activity — Mac side (`D/push.py`)

| Event | Gate | Cite |
|---|---|---|
| session `busy` → not busy | folder's `finished`; a first sighting (`was is None`) is suppressed | `D/push.py:196-209` |
| a new unanswered slip appears | folder's `slips` | `D/push.py:210`, `:223-243` |
| a waiting session disappears | none | `D/push.py:211-214` |
| `POST /notify` — an agent asking for the person in its own words | folder's `called`; the refusal is returned to the caller | `D/push.py:246-258` |
| answering a session re-announces the remaining count | none | `D/push.py:261-265` |

- Payload update: `{"aps":{"timestamp":int,"event":"update","content-state":{waiting,name,line,when}}}`; start adds `attributes-type: "Deck"`, `attributes:{mac}` and an `alert` — `D/push.py:130-142`.
- `line` prefers the agent's own words, else the first 120 chars of its last assistant text — `D/push.py:275-287`.
- Transport: HTTP/2 to `api.sandbox.push.apple.com`, `apns-topic dev.jurrejan.deckhand.push-type.liveactivity`, `apns-push-type liveactivity`, priority 10, 10 s timeout — `D/push.py:145-153`, `:31-36`.
- JWT ES256, `iss KA6433FU8U`, `kid` from `apns-key-id`, cached `JWT_LIFETIME = 45 min` — `D/push.py:93-109`.
- Sandbox host is deliberate: it must match the app's `aps-environment: development` entitlement — `D/push.py:29-31`, `deckhand/Deckhand.entitlements:5-9`.
- Failure modes, all strings: no key pair → "run `just sync-apns`"; unreadable key; activity token refused → falls through to the start token; no token registered; `httpx.HTTPError`; non-200 with APNs' `reason` — `D/push.py:118-161`.

---

## 12. Mac-side UI — Deckhand's page inside utt (`D/plugin.py`)

| Item | Kind | Default / effect | Cite |
|---|---|---|---|
| `route` | setting, choice | "whichever works" → `auto/keyboard/socket`, used when the phone sends no `?route=` | `D/plugin.py:125-129`, `:71-73` |
| `deliver` | setting, bool | true; off = transcribe and show on the phone, deliver nothing | `D/plugin.py:130-133`, `D/saying.py:88` |
| `attribution` | setting, string | `"JJ, spoken:"` → overwrites `deliver.PREAMBLE`, the socket-route prefix | `D/plugin.py:134-137`, `:202` |
| `copyToken` | action | pbcopy the pairing token | `D/plugin.py:119`, `:210-212` |
| `openLog` | action | `open -a Console` on the daemon log | `D/plugin.py:121`, `:213-214` |
| Manifest identity | `id deckhand`, `systemImage sailboat`, `tint #3EAFB4`, `needsApi false`, `sendsAudio true`, `skipsTextStages ["formatting"]`, `showsInMenuBar true`, `daemon.label` | `D/plugin.py:81-139` |
| Status line back to utt | `daemon`, `version`, `sessions`, `briefings`, `lastAction`, `lastClip` | `D/plugin.py:151`, `D/app.py:87,130,260`, `D/saying.py:86` |
| Read protocol | values applied only when `revision` changes (whole-file replace); actions fire only on a strictly increasing `sequence`, never on first sight | `D/plugin.py:181-203` |
| Folder probe | `extensions/` or `plugins/` under `dev.jurrejan.utt`, newest name first (utt 1.2 rename) | `D/plugin.py:31-54` |
| `showsInMenuBar` is all-or-nothing | every action must be safe to press by accident | `D/plugin.py:111` |

---

## 13. The agent-facing skill (`skills/deckhand/`)

| Item | What it is | Cite |
|---|---|---|
| `SKILL.md` | when a slip beats a sentence; writing one by script or by hand; the CSP rules; the four injected hooks; the aloud block; `/notify` by curl | `skills/deckhand/SKILL.md:17-109` |
| Four hard refusals | never pass `route`, never `POST /control`, never `PUT /settings` or `…/filters`, never `POST /projects/session` — **unenforced today, one shared token** | `skills/deckhand/SKILL.md:111-125` |
| `reference/wire.md` | every route with its trap | `skills/deckhand/reference/wire.md` |
| `reference/traps.md` | prefill from `answer`, `delivered` vs said, the inbox, why `null` is refused, the CSP | `skills/deckhand/reference/traps.md` |
| `scripts/slip.py` | writes a `confirm\|pick\|text\|aloud` page by substituting into the demo pages; slug `[A-Za-z0-9][A-Za-z0-9_-]{0,63}` so `..` is unspellable; exits non-zero if an anchor is gone; deletes the answer on rewrite (rewriting is re-asking) | `skills/deckhand/scripts/slip.py:36`, `:45-54`, `:167-170` |
| `scripts/answer.py` | prints the answered value or exits 1; `--wait` polls every 2 s; a half-written file is "not answered"; `found` is separate so `false`/`0`/`""`/`[]` survive | `skills/deckhand/scripts/answer.py:29-39` |
| `templates/` | six symlinks into `demos/`, so `just demo-check` gates both copies | `skills/deckhand/templates/` |
| Installed | `~/.claude/skills/deckhand` → the repo folder (symlink present on this Mac; **no `just` recipe creates it**) | verified `readlink -f`; `grep -in skill Justfile` → no match |

---

## 14. iOS app (`deckhand/`)

### 14.1 Screens, sheets and overlays

| Surface | Shows | Reached by | Cite |
|---|---|---|---|
| `RootView` | picks by aspect ratio: landscape → deck, portrait → rail; installs the mermaid renderer app-wide | app launch | `deckhand/App.swift:34-52` |
| `SessionListView` (rail, forced dark) | grouped Favourites/Sessions rows, foot strip: wordmark, reason, statusline, state word, +session, eye, gear | root, portrait | `Views/SessionListView.swift:70-75`, `:86-91` |
| `DeckView` (deck, the landscape rail) | starred sessions as columns, min width 240 then sideways scroll, BRIEF/LIVE flip, 6 turns per column | landscape | `Views/DeckView.swift:17`, `:41`, `:233-245` |
| `SessionView` (page surface, no nav bar) | `SessionHead` + four-pane `TabView(.page)` + `SessionFoot` | tap a row | `Views/SessionView.swift:182-188` |
| pane 1 `BriefingView` | waiting slip → briefing prose → ask list → spend line | swipe | `Views/BriefingView.swift:6-83` |
| pane 2 `ArtifactsView` | All/Waiting/Answered capsules + slip rows | swipe | `Views/Artifacts/ArtifactsView.swift:53`, `:112-132` |
| pane 3 `TranscriptView` | tool traces, turn cards, active line, queued cards, "Earlier" | swipe | `Views/TranscriptView.swift:19-152` |
| pane 4 `FilesView` | suffix/CLAUDE capsules over a flat asset list or the context tree | swipe | `Views/FilesView.swift:20-155` |
| `SettingsView` sheet | see §14.5 | gear in the rail foot | `Views/SettingsView.swift:25`, `:113` |
| `ProjectListView` sheet | search field + project rows + a caveat line naming the source | "New session" | `Views/Projects/ProjectListView.swift:46`, `:209-216` |
| `ProjectSettingsView` sheet | per-folder switches and models, sessions running here | long-press a project row, or the session menu | `Views/Projects/ProjectSettingsView.swift:58`, `:171` |
| `ArtifactView` full-screen cover | aloud cards or the page, receipt row, × | a slip row, or the waiting slip | `Views/Artifacts/ArtifactView.swift:159-160`, `:203` |
| `AssetView` sheet | image (markable), text (markdown or source), video | a file row or a context row | `Views/AssetView.swift:177-188` |
| `RawView` sheet | one wrapped line per JSONL event, bottom-anchored, count footer | menu → "Raw transcript" | `Views/TranscriptView.swift:202` |
| `SessionFilters` sheet | the session's chain, up/down, per-kind controls; saves on dismiss | menu → "Words on the way in…" | `Views/Session/SessionFilters.swift:39-42` |
| `Renaming` sheet | name field + dictation, warning line | menu → "Rename…" | `Views/Session/Renaming.swift:14-89` |
| `ArchiveSheet` | every kept clip, newest first, sweep rule in the footer | the mark on `SessionFoot` only | `Views/Archive/ArchiveSheet.swift:45-59` |
| `SnapView` sheet | an attached picture in `Marking`; Remove / pencil / Send / Close | tap a pinned thumbnail | `Views/Annotation/SnapView.swift:47` |
| `Editor` sheet | full-screen text editor with dictation above the keyboard | review card → "Edit" | `Views/Session/Editor.swift:59`, `deckhand/Dictating.swift:47` |
| `CommandPicker` sheet | searchable slash commands and skills, `project`/`skill` tags | review card → "Command" | `Views/Session/CommandPicker.swift:12-105` |
| `ReviewCard` | the words, add-more, filter notes and refusals, thumbnails, actions | appears when a clip has been transcribed with `deliver=false` | `Views/Session/SessionFoot.swift:25`, `deckhand/Snaps.swift:93-100` |
| Overlays | pane-name landing capsule, edge fade mask, control confirmation dialog, "Open where?" for a localhost link | — | `Views/SessionView.swift:216-233`, `:200-208`, `:140-155`, `Views/LocalLinks.swift:28-38` |

### 14.2 Gestures and constants

| Gesture | Constant / rule | Cite |
|---|---|---|
| Same-touch guard | `sameTouch = 0.6 s` — a follow-up tap from one physical press is ignored | `Views/TalkControl.swift:8`, `:115-118` |
| Hold to talk | `TalkGesture.settle = 0.2 s` long-press before recording starts | `Views/TalkControl.swift:185` |
| Reach the archive | `longer = 0.45 s` long-press | `Views/TalkControl.swift:189` |
| Four gesture shapes | hold+pressToStart, plain hold, toggle+pressToStart, toggle+reach — Settings picks | `Views/TalkControl.swift:196-236` |
| Rail row | tap opens, settled press dictates straight from the row, swipe-leading stars, swipe-trailing hides | `Views/SessionListView.swift:160-173` |
| Pull to refresh | on the rail list | `Views/SessionListView.swift:115` |
| Scene re-activation | forces a refresh | `Views/SessionListView.swift:79-82` |
| Deck column | the whole column is the press target; no tap-to-start | `Views/DeckView.swift:90-100` |
| Orientation | portrait ↔ landscape swaps rail ↔ deck; recording pins the current orientation | `deckhand/App.swift:39-43`, `deckhand/OrientationLock.swift:14-17` |
| Custom swipe-back | nav bar hidden, so: drag ≥30, only on pane 1, `startLocation.x < 28`, `width > 80`, `|height| < 80` | `Views/SessionView.swift:159-172` |
| Pane paging | `TabView(.page)`, 0.25 s snappy; landed label 0.2 s in, hides after 1.1 s | `Views/SessionView.swift:246-253`, `:99-106` |
| Tool trace depth | head tap cycles dots → list → everything → dots | `Views/ToolTrace.swift:19-30` |
| Picture | single tap drops a pin (requires the double tap to fail), double tap zooms to that spot, pinch to 12×, pan; pencil hands touches to PencilKit | `Views/Annotation/PictureScroll.swift:128-149`, `:191-202` |
| Clip row | swipe to delete; menu Copy / Send to… / Delete | `Views/Archive/ArchiveSheet.swift:45`, `Views/Archive/ClipRow.swift:84-97` |
| Poll rates | rail 4 s, briefings 12 s, session turns 5 s, deck 6 s | `Views/SessionListView.swift:74`, `:90`, `Views/SessionView.swift:187`, `Views/DeckView.swift:41` |
| Paging | first page 25, ceiling 200, poll limit `min(200, max(25, count))` | `deckhand/Reading.swift:15-27` |
| Keyboard shortcuts | **none exist** — verified, only `onSubmit` in `Renaming.swift:80` | — |

### 14.3 Recorders, clips and the archive

| Feature | Detail | Cite |
|---|---|---|
| `Recorder` | one clip at a time, 16 kHz mono AAC into `tmp/`, metering every 0.05 s dBFS → amplitude, holds the orientation lock and keeps the screen awake; a press under 0.3 s is discarded | `deckhand/Recorder.swift:35-46`, `:69-86` |
| Keep before the wire | `Keeping.upload` files the clip in the archive **before** uploading, then writes the outcome back onto the entry | `deckhand/Keeping.swift:19-51` |
| Dictation | `Dictating.dictated` uploads with `deliver=false`, returns the words, deletes the tmp clip, is **not** archived | `deckhand/Dictating.swift:34-58` |
| `TalkControl` | the one gesture host; `TalkState` carries cancel / stop / tapped | `Views/TalkControl.swift:12-140` |
| `TalkMark` | `DotMark.live` 40 pt on its own dark tile, two wings (tap-sends, CANCEL in toggle mode); `clearance = 68` every scrolling pane adds | `Views/Talk/TalkMark.swift:31-51`, `:124-129` |
| Add more | `SayRest` lays a second clip **under** the card's words via `deliver=false`; Add → Done → "Adding…" | `Views/Session/SayRest.swift:27-37`, `deckhand/Appending.swift:67-89` |
| Dictate into a field | `SayInto` — field binding with a gap, or a free `heard` closure | `Views/Session/SayInto.swift:39-72` |
| Archive | list + sweep rule (`sweptAfterDays = 7`), play/stop, transcript up to 6 lines, failure in red, orphan wording | `Views/Archive/ArchiveSheet.swift:54-59`, `Views/Archive/ClipRow.swift:43-79`, `Views/Archive/ClipPlayer.swift:23-50` |
| Resend a clip that never arrived | `POST /say?prepared=true`, then `markSent` | `deckhand/Keeping.swift:130-145` |
| Sweep | runs once on app open | `deckhand/App.swift:24` |

### 14.4 Marking up a picture

| Step | Detail | Cite |
|---|---|---|
| Picture in | a Mac file downloaded in `AssetView`, or a snap already pinned to the card | `Views/AssetView.swift:177-188`, `Views/Annotation/SnapView.swift:47` |
| Drop a spot | tap → `Fitting.pixel` converts to the picture's own pixels → a `Pin` is appended and chosen | `Views/Annotation/PictureScroll.swift:139-149` |
| Markers | live outside the zoom transform at a constant 26 pt, repositioned on every zoom/pan/fit, with a deferred second report | `Views/Annotation/PictureScroll.swift:217-260`, `Views/Annotation/Markup.swift:65` |
| Callout | 248 pt wide max, 22 pt clear of the marker, flips above when it will not fit; Say / Replace / Delete, no text field | `Views/Annotation/PinCallout.swift:18-86` |
| Dictated remark | **replaces** the pin's words — the one place `Underneath.words` is deliberately not used | `Views/Annotation/Marking.swift:134-138` |
| Freehand | PencilKit inside the image view, strokes kept in picture pixels and rescaled on every fit | `Views/Annotation/PictureScroll.swift:166-213` |
| Flatten | drawing plus achromatic numbered discs burned in at scale 1, full pixel size | `Views/Annotation/Markup.swift:31-46`, `:128-145` |
| What the session is told | the marked PNG (`<stem>-marked.png`) is pinned as a snap; `Pin.prose` puts the numbered remarks **under** the words, naming the original's path or saying both copies are attached | `deckhand/Markups.swift:53-140`, `deckhand/Snaps.swift:74-81` |
| Nothing is sent from the sheet | the card's own Send uploads pictures, then `POST /say` | `deckhand/Snaps.swift:87-103` |
| Markups survive the sheet | keyed by `asset.path` or `snap:<uuid>`; an emptied one is forgotten | `deckhand/Markups.swift:24-45`, `:76-86` |

### 14.5 Settings

| Control | Cite |
|---|---|
| Mac address, token, "Check connection" (`GET /health`) | `Views/SettingsView.swift:43`, `:52`, `:60` |
| Five triggers — finished / slips / called / chase / subagents — with a "Per project" caption | `Views/SettingsView.swift:76-84` |
| Two model pickers — new sessions, summaries — offers read from the Mac | `Views/SettingsView.swift:94-95` |
| Talking button mode (hold / tap), read-it-first, route picker | `Views/SettingsView.swift:143`, `:155`, `:160` |
| Unhide hidden sessions | `Views/SettingsView.swift:172-181` |
| Version + connection footline | `Views/SettingsView.swift:187` |
| **Per-project settings screen exists** — same seven keys as `Overrides`, an "only here" marker per overridden key, "Follow the Mac for everything here", and the sessions running in that folder with compact/exit | `Views/Projects/ProjectSettingsView.swift:80-101`, `:108-140`, `:211-218` |
| Phone-only preferences not on the Mac | talk mode, confirms, route, hidden, formatsMarkdown — `Sources/DeckhandKit/Preferences.swift` |

### 14.6 Slips on the phone

| Feature | Detail | Cite |
|---|---|---|
| Listing | filter capsules only when waiting and answered both exist; answered rows recede to 0.72 and swap the icon | `Views/Artifacts/ArtifactsView.swift:112-132`, `:166-203` |
| One decision | `aloud = Aloud.declared(in: text)` is set **before** `html`, so one pass picks cards or page | `Views/Artifacts/ArtifactView.swift:62-80` |
| Aloud render | one card per declared question (index eyebrow, ask, hint), a real talk mark per card with its own accent, plus a text field fallback; words go under what is there | `Views/Artifacts/AloudCards.swift:80-154`, `:186-193` |
| Page render | `WKWebView` with `ArtifactPage.armoured` CSP, exactly one navigation allowed, non-persistent store, no back/forward, no link preview, no data detectors, transparent | `Views/Artifacts/ArtifactWeb.swift:41-91` |
| Say on a page | `SayOnPage` in a bottom safe-area inset, only for a plain HTML slip; driven by what the page's watcher reports (`none`/`quote`/`field`) | `Views/Artifacts/ArtifactView.swift:144-153`, `Views/Artifacts/SayOnPage.swift:36-84` |
| Talking into a field | two JS round trips; an `input` event is dispatched, `change` deliberately never | `Views/Artifacts/PageTalk.swift:41-94` |
| Commenting on a selection | goes to the review card as a remark heading into the session's inbox; the page never sees it | `Views/Artifacts/SayOnPage.swift:36-84`, `Sources/DeckhandKit/Artifacts/Quoting.swift:17` |
| Submitting | a page's `respond(value)` is fire-and-forget; cards await, set a receipt, dismiss only on `sent.went`, and refuse a second tap while sending | `Views/Artifacts/ArtifactView.swift:186-211`, `Views/Artifacts/AloudCards.swift:206-214` |
| Prefill | the answer JSON is fetched first and handed in with the page, or seeded into card state via `Aloud.said(in:)` | `Views/Artifacts/ArtifactView.swift:33`, `:66`, `:72` |
| Send label | "Send N of M" / "Send all N" / "Sending…" | `Views/Artifacts/AloudCards.swift:199-204` |

### 14.7 The rest of the app

| Feature | What it does | Cite |
|---|---|---|
| Transcript reader | tool traces above words, an active line for a busy session, queued cards for the inbox, "Earlier" paging that re-anchors one runloop hop later | `Views/TranscriptView.swift:19-152` |
| Context tree | every CLAUDE.md with the Mac's own connectors in monospace, per-doc tokens in `4.2k` shorthand, a total line; a row opens the doc | `Views/Session/ContextTree.swift:18-93` |
| File browser | horizontal All/CLAUDE/suffix capsules over a flat asset list (size · age · folder) | `Views/FilesView.swift:20-155` |
| Command picker | searchable, tagged `project`/`skill`, the chosen name goes in front of the draft | `Views/Session/CommandPicker.swift:12-105` |
| Renaming | field + dictation, runs Claude Code's own `/rename` in the pane, Rename disabled when blank | `Views/Session/Renaming.swift:14-89` |
| Ask list | last 8 asks as tickable dots with an "N OF M DONE" tally and an "older, on the Mac" footnote | `Views/AskList.swift:9-116` |
| Statusline | the week's token share (amber over pace) plus what the rail is running | `Views/Statusline.swift:16-37` |
| Tool trace | three depths; failures lead the closed label; selectable CALL/RESULT blocks at the deepest | `Views/ToolTrace.swift:10-136` |
| Mermaid | bundled mermaid 11.12.3 as a user script; the page measures and posts its own height (start 140, ceiling 1400); zero falls back to source; re-renders on theme change | `Views/Diagrams/MermaidBlock.swift:22-103` |
| Local links | intercepts `openURL` for localhost and offers the Mac's LAN address vs the paired host | `Views/LocalLinks.swift:11-39` |
| Asset view | downloads to disk, opens image / text / video; markdown has a source↔formatted toggle wired to preferences | `Views/AssetView.swift:12-249` |
| Controls | cancel / compact / clear / exit with a confirmation carried on the control itself; `clear` is the only irreversible action | `Views/SessionView.swift:140-155`, `Sources/DeckhandKit/Control.swift:13-76` |
| Live Activity, client side | watches push-to-start tokens forever and every activity's own token, hex-encodes and `POST`s each distinct value once; **starts no activity and pushes no content** | `deckhand/LiveUpdates.swift:36-83` |

---

## 15. DeckhandKit (`Sources/DeckhandKit/`)

### 15.1 Models on the wire

| Type | Notable | Cite |
|---|---|---|
| `Pane` | the iTerm pane; the whole struct is `Session.pane?`, absent when iTerm is unreachable | `Models.swift:4` |
| `Session` | `context`, `artifactsWaiting`, `artifactsAnswered`, `model`, `effort` all optional; `==`/`hash` on `sessionId` only | `Models.swift:12` |
| `ContextWindow` | named so because `Context` clashes with `UIViewRepresentableContext`; `share`, `line`, `Pressure` bands at .75/.9 | `Models.swift:69` |
| `Delivery` | hand-written init, every field `decodeIfPresent`; **`went = delivered && stoppedBy == nil`** | `Models.swift:104`, `:117` |
| `UploadReceipt` | `prepared` only on `deliver=false`; `words = prepared ?? transcript` | `Models.swift:130`, `:157` |
| `Health` | `lan` and `iterm` optional (an older Mac) | `Models.swift:175` |
| `Asset` | `kind` string → image/video/text; `folder` strips the last component | `Models.swift:187` |
| `DeckhandError` | unauthorized / notLive / http(code, body) / badResponse; `detail` decodes FastAPI's `{"detail"}` | `Models.swift:221` |
| `Turn`, `Rounds`, `Queued`, `Tool`, `Doc`, `ContextDocs` | tolerant decoders throughout; `Tool.succeeded` defaults **true**; `Doc.prefix` is the connector the Mac already drew | `Conversation.swift:8`, `:51`, `:82`, `:98`, `:155`, `:193` |
| `Summary`, `Spend`, `Ask` | `writtenAt == nil` ⇒ `isUnwritten`; `Spend.line` "3 briefings · 1.2k tokens"; `Ask.state` → todo/doing/done | `Briefing.swift:8`, `:44`, `:75` |
| `Listing`, `Week` | `week` read through `try?` so a newer week object cannot lose the rail; `pctUsed` may exceed 100 and is never clamped | `Listing.swift:9`, `:23`, `:31` |
| `JSONValue` | any JSON carried unchanged; decode order **int before double** is the correctness | `Filters.swift:15`, `:24` |
| `FilterField`, `Filter`, `FilterStep`, `FilterRow`, `FilterOffer`, `FilterChain` | `default` → `defaultValue`, `on` → `isOn` defaulting true; `FilterRow` carries a UUID because a filter may appear twice | `Filters.swift:113`, `:163`, `:192`, `:226`, `:254` |
| `Control`, `Caution` | raw values are `deliver.CONTROLS` keys; the question lives on the control, not the sheet | `Control.swift:13`, `:57`, `:76` |
| `Project`, `Catalog` | everything below `path` defaulted; `id = path` (names collide); `matches` requires all words to land, not all in one field; `caveat` turns the source into a sentence | `Projects/Project.swift:11`, `:143`, `:165` |
| `Wants`, `Overrides`, `Settings` | `session_model`/`summary_model` **spelled out in `CodingKeys`** so a converting decoder throws instead of losing them; `projects` keys are folder paths → no key strategy anywhere | `Settings/Wants.swift:8`, `:41`, `:79`, `:107` |
| `ServerSettings` | accepts a bare name, `host:port` or a full URL; default port 4180 | `ServerSettings.swift:4`, `:17` |
| `SlashCommand` | `infront(of:)` replaces a leading command; `arguments` needs a name-ish head so a path is not eaten | `SlashCommand.swift:9`, `:39`, `:50` |
| `Artifact`, `ArtifactList` | `id` is the slug and the filename; `answered` flips both ways | `Artifacts/Artifacts.swift:8`, `:36` |
| `Aloud`, `Aloud.Question` | parsed from `id="deckhand-aloud"`; duplicate ids dropped, first wins; any failure ⇒ nil ⇒ the page renders | `Artifacts/Aloud.swift:25-56` |
| `Pin` | in image pixel space; `prose` in two forms (a Mac file vs an attachment) | `Markup.swift:12`, `:34`, `:59` |
| `Deck` / `Deck.ContentState` | `when` is **Unix seconds, not `Date`** — no Swift on the sending side | `LiveActivity.swift:13-14` |
| `TalkMode`, `DeliveryRoute`, `Preferences` | stars and hidden keyed by **name**, carried by `renamed(from:to:)`; `formatsMarkdown` read via `object(forKey:)` because a missing key reads false and the default is on | `Preferences.swift:4`, `:39`, `:83`, `:112` |
| `KeptClip`, `ClipArchive` | `isOrphan` = not delivered, no failure; `delivered` written from `Delivery.went` | `Clips/ClipArchive.swift:8`, `:54` |

### 15.2 HTTP client

All carry the token, 20 s default timeout, throw `DeckhandError` (`DeckhandClient.swift:221`).

| Method | Route | Note | Cite |
|---|---|---|---|
| `health()` | `GET /health` | | `DeckhandClient.swift:15` |
| `sessions()` | `GET /sessions` | | `:20` |
| `summary(of:)` | `GET /sessions/{id}/summary` | off disk, no long timeout | `:29` |
| `briefings()` | `GET /briefings` | | `:35` |
| `files(of:)` | `GET /sessions/{id}/files` | | `:42` |
| `commands(of:)` | `GET /sessions/{id}/commands` | | `:52` |
| `download(_:in:)` | `GET /sessions/{id}/file?path=` | 300 s, own status check, temp file keeps the extension | `:66` |
| `turns(of:limit:before:)` | `GET …/turns` | `before` counts backwards from the tail | `:97` |
| `raw(of:limit:)` | `GET …/raw` | | `:103` |
| `say(_:to:route:images:prepared:)` | `POST …/say` | 30 s | `:111` |
| `upload(image:named:to:)` | `POST …/image` | multipart, 120 s | `:138` |
| `register(pushToken:kind:)` | `POST /live/token` | | `:156` |
| `control(_:of:)` | `POST …/control` | | `:165` |
| `rename(_:to:)` | `POST …/name` | returns `carriedFilters` | `:174` |
| `clearQueue(of:)` | `POST …/queue/clear` | | `:184` |
| `focus(_:)` | `POST …/focus` | | `:189` |
| `upload(clip:to:route:deliver:)` | `POST …/audio` | **200 s** — utt loads its model | `:194` |
| `context(of:)` | `GET …/context` | | `Conversation.swift:205` |
| `filters(of:)`, `saveFilters(_:of:)` | `GET`/`PUT …/filters` | decoded **`literally`**, no key strategy | `DeckhandClient+Filters.swift:16`, `:29`, `:43` |
| `projects()`, `startSession(in:)` | `GET /projects`, `POST /projects/session` | 30 s cold atlas / **90 s** start | `Projects/DeckhandClient+Projects.swift:12`, `:27` |
| `settings()`, `saveSettings(_:)` | `GET`/`PUT /settings` | decoded **`plain`**, no key strategy | `Settings/DeckhandClient+Settings.swift:13`, `:22` |
| `artifacts(of:)` | `GET …/artifacts` | **404 ⇒ `[]`** on purpose | `Artifacts/Artifacts.swift:63` |
| `page(of:in:)`, `answered(_:in:)`, `answer(_:in:valueJSON:route:)` | the three artifact routes | `answer` parses the JSON before forwarding — the app is the boundary | `Artifacts/Artifacts.swift:75`, `:92`, `:116` |

Routes the client never calls: `GET /filters` (the per-session call carries `known`), `GET /settings/project` (re-implemented as `Settings.resolved(for:)`, `Settings/Wants.swift:124`), `POST /sessions/{id}/notify` (an agent's route). No client method calls a route that no longer exists.

### 15.3 Pure logic

| Piece | What it computes | Cite |
|---|---|---|
| `Listing` | Mac-wide facts carried on the request the rail makes anyway; `Session.family` trims `claude-sonnet-5` → sonnet; `Session.running(_:)` collapses a whole rail into one footer line | `Listing.swift:9`, `:69`, `:81` |
| `Grouping` | the Files tab's sections by suffix; biggest-first with an alphabetical tiebreak so the list does not reshuffle | `Grouping.swift:13-54` |
| `Fitting` | screen ↔ image-pixel arithmetic for markup; nil outside the letterbox — the markup bug that would fail silently | `Fitting.swift:18-34` |
| `Underneath.words` | dictation appends under standing text, never replaces | `Underneath.swift:20` |
| `Quote.prose` | review-card prose for a passage out of a slip; `longest = 1500`, cut on a word boundary with an honest ceiling line | `Quoting.swift:17`, `:34`, `:61` |
| `Aloud` | `declared(in:)` as string work (no WebKit, so it is testable on the Mac); `said(in:)`; `value(of:)` writes `{"answer":{…},"completedCount":n}` | `Artifacts/Aloud.swift:56`, `:91`, `:107` |
| `ArtifactPage` | the feature's security boundary: the CSP (`default-src 'none'`, no network of any kind), `armoured` prepends it before the page's first token, `bridge` defines a frozen `window.deckhand` (`respond`, `close`, `artifact`, `answer`), `watcher` reports only field/quote/none, never text | `Artifacts/ArtifactPage.swift:21`, `:48`, `:95`, `:137` |
| `ArtifactStyle` / `ArtifactTokens` | the design layer as one injected stylesheet; element selectors and single classes only, no `!important` except `[hidden]`, so a page can take it back | `Artifacts/ArtifactStyle.swift:20-24`, `ArtifactTokens.swift:8` |
| `ClipArchive` | clips move into Application Support **before** the upload, so no window exists where the only copy is in tmp; `keep`, `finish`, `markSent`, `remove`, `sweep` (7 days, delivered only), atomic index write | `Clips/ClipArchive.swift:58-162` |
| `Markup` | `Pin.prose` in two forms, numbering shared so a marker and its remark can never disagree | `Markup.swift:34`, `:59`, `:75` |
| `Preferences` | stars, hidden, route, talk mode, confirm, markdown; `setHidden` un-stars | `Preferences.swift:39`, `:88` |
| `Markdown.Block.parse` | fence state, table runs, `#`–`###`, `3. ` keeps the document's own number, one step of nesting max | `Design/MarkdownBlocks.swift:19-86` |

### 15.4 Design layer (a port of utt's `swift/utt/Utt/Design/`)

| File | What it provides | Cite |
|---|---|---|
| `Palette` | `tint` #3EAFB4, `recording` #D4501E, `lcdGround` #303027 (never black), LCD green/yellow/red, hairline .08, three text levels, `pressure(_:)` | `Design/Palette.swift:8-55` |
| `Typography` | `pageTitle` 20 semibold, `lead` 17, `prose`/`primaryRow` 14, rail rows 13, `subtitle` 12, `mono` 12, `hint` 11, `cardLabel` 11, `groupLabel` 10, `state`/`eyebrow` 9 mono | `Design/Typography.swift:4-24` |
| `Spacing` / `Radius` | 4/8/12/16/24/32 and 8/12/16/20/999 — nothing between the steps | `Design/Spacing.swift:4`, `:14` |
| `Chrome` | `Card`, `SettingsGroup` (never a card in a card), `SettingRow`, `PageHeader`, `Meter` (3 pt capsule, no number of its own) | `Design/Chrome.swift:5`, `:31`, `:62`, `:96`, `:137` |
| `Accent` | `@Entry var accent`, `Palette.accent(recording:)`, `.accent(_:)` sets environment and `.tint` with a 0.2 s crossfade (no spring — it would fight the dot clock) | `Design/Accent.swift:16-39` |
| `DotMark` | 6×6 canvas, lit dots 0.34 of a cell, unlit 0.24 at .28 alpha, `hotCore` radial gradient, `live(...)` fade capped at `min(0.4, cycle*0.5)`; `Wordmark` writes the name with the period in the accent | `Design/DotMark.swift:9-126` |
| `DotMatrix` | `rect(for:)`, `tick` 0.05 s, 6 s cycle → 0.1 s geometric, `quietestGlow` 0.45, dBFS loudness curve; `DotGlyph.anchor` plus seven session glyphs, `forName` via **FNV-1a** so a face survives a cold start | `Design/DotMatrix.swift:10-81` |
| `DotPatterns` | utt's ~130-frame show copied verbatim | `Design/DotPatterns.swift:10` |
| `DotMatrixDriver` | one shared observable clock — per-view timers drift and two marks would never agree | `Design/DotMatrixDriver.swift:13` |
| `Drawn` | `@Entry var diagram` and `.diagrams(_:)`; nil is a working default, which keeps a web view out of the module | `Design/Drawn.swift:17`, `:22` |
| `Fade` | `floor` 0.5, `grace` 120 s, `span` 8 h, logarithmic contrast (1 h ≈ 0.69); a busy session is always 1 because `updated_at` is a change, not a heartbeat | `Design/Fade.swift:19-48` |
| `Links` | local host set, `NSDataDetector` leaving markdown links alone, UTF-16 range conversion, `choices(for:mac:paired:)` | `Design/Links.swift:12-69` |
| `Markdown` | the renderer for a markdown file **and for a turn** (a turn has no contract to break, and one session writes another markdown); headings 20/17/14, body 14 with 6 pt line spacing, bullets as a 4 pt grid dot, numbered keeps the document's number, `Verbatim` one `Text` per line inside a horizontal scroll (one wide `Text` renders nothing past a few thousand points) | `Design/Markdown.swift:15-212` |
| `Prose` | the summary renderer — exactly four things, a contract shared with the daemon's prompt; compact deck sizes 9/11/8 | `Design/Prose.swift:12-113` |
| `StateWord` | ON/OFF/WAIT/IDLE/BUSY/ERR/REC as 9 pt mono tracked 2, **no badge, no capsule**; `GlyphTile` = the mark at 0.62 of the tile | `Design/StateWord.swift:5-57` |

---

## 16. Widgets — the Live Activity (`widgets/DeckhandWidgets.swift`)

| Presentation | Draws | Cite |
|---|---|---|
| Lock screen | 34 pt anchor mark with `hotCore: 0.3`, the waiting block, a trailing column of state word + the Mac's name; `lcdGround` tint, forced `.dark` — the rail, not a page | `widgets/DeckhandWidgets.swift:69` |
| Compact leading / trailing | 16 pt anchor mark / the count in `eyebrow` tint | `:29`, `:32` |
| Minimal | the same 16 pt mark | `:35` |
| Expanded island | leading 22 pt mark (no extra padding — the top row is height-locked to the camera), trailing state word, bottom the waiting block full width | `:53-63` |
| `Waiting` | "Nothing waiting" / the name / "3 waiting · utt", a relative age with `.fixedSize()` (a clipped age is a wrong number), and `line` at 2 lines with `.fixedSize(horizontal: false, vertical: true)` so the region grows instead of slicing line two | `:94-127` |
| Wire contract | attributes `Deck{mac}`; state `waiting: Int`, `name: String`, `line: String`, `when: Double` (Unix seconds); matches `D/push.py:131`, `:138` | `Sources/DeckhandKit/LiveActivity.swift:13-34` |
| Deep link | `widgetURL(deckhand://waiting)`, `keylineTint(Palette.tint)` | `:38-39` |

---

## 17. Tooling

### 17.1 `just` recipes

| Recipe | Does | Cite |
|---|---|---|
| `default` | lists recipes, prints the branch | `Justfile:4` |
| `install` | `swift package resolve` + `uv sync --all-groups`, warns on missing swiftlint/xcodegen | `Justfile:14` |
| `generate` / `xcode` | `xcodegen generate` / then open the project | `Justfile:21`, `:25` |
| `daemon` | run the daemon in the foreground | `Justfile:30` |
| `sync-apns` | `onenv get deckhand APNS_KEY` → `apns.p8` + `apns-key-id`, 0600 (launchd cannot run onenv) | `Justfile:37` |
| `logs` | tail the daemon log | `Justfile:46` |
| `icon` | `swift run IconMaker …/AppIcon.appiconset/icon.png` | `Justfile:51` |
| `token` | print the pairing token | `Justfile:56` |
| `sim` / `device` | build, install and launch already paired (`-deckhand.host`, `-deckhand.token`) | `Justfile:61`, `:76` |
| `lint` / `lint-fix` | `swiftlint lint --strict` / `--fix` then relint | `Justfile:83`, `:87` |
| `just-fmt-check` | `just --fmt --check` | `Justfile:91` |
| `test` / `daemon-test` / `daemon-lint` | `swift test` / `pytest -q` / `ruff check` | `Justfile:95`, `:99`, `:103` |
| `demo-check` | `python3 demos/check.py` | `Justfile:108` |
| `ui-test` | passes `TEST_RUNNER_DECKHAND_TOKEN/HOST` into `xcodebuild test` | `Justfile:113` |
| `loc-check` / `dir-check` | file line caps and files-per-directory from `.quality.json` | `Justfile:118`, `:140` |
| `check` | the gate — see below | `Justfile:167` |
| `build` / `build-release` / `clean` | generate + both builds / release SwiftPM / drop products | `Justfile:188`, `:193`, `:197` |
| `claude-tree` | `atlas tree` — the CLAUDE.md tree in project-atlas's viewer | `Justfile:203` |
| `update-scaffold` | pull cookiecutter template updates | `Justfile:207` |
| `install-agent` / `uninstall-agent` | symlink + bootstrap the plist then poll `/health` / bootout + unlink | `Justfile:222`, `:228` |

### 17.2 The quality gate

- `just check` order: `just-fmt-check` → `loc-check` → `dir-check` → `lint` → `build` (generate + `swift build` + iOS `xcodebuild`) → `test` → `daemon-lint` → `daemon-test` → `demo-check` (`Justfile:167-185`).
- `.quality.json`: warn 300 / **error 400** lines, max **16 files** per directory, globs `deckhand/**`, `Sources/**`, `Tests/**`, `UITests/**`, `daemon/src/**`, `daemon/tests/**` (`.quality.json:3-16`). The warn text says "don't trim, split the file!" (`Justfile:134`).
- SwiftLint: excludes `.build`, `Packages`, `.worktrees`, `.claude` (nested agent worktrees otherwise lint another checkout); function body 20/40, file length 300/400; `todo` and `line_length` disabled (`.swiftlint.yml:1-37`).
- Custom rule `bare_nsapp_activate`, severity **error** — a no-op under macOS 14 cooperative activation for an LSUIElement app (`.swiftlint.yml:23-33`).

### 17.3 Icon maker, demos, UI tests, build config

| Feature | Detail | Cite |
|---|---|---|
| Icon maker | 1024 px canvas, grid at 0.74 (squircle mask), palette values copied so it needs no SwiftUI, opaque `noneSkipLast` bitmap (App Store rejects alpha, ITMS-90717), 36 cells from `DotGlyph.anchor` + `DotMatrix.rect` — the same grid as the in-app mark | `Sources/IconMaker/main.swift:12-72` |
| Demos | six pages, one per `consult-user-mcp` dialog plus the phone-only aloud shape; each answers via `window.deckhand.respond(value)` in the shape that dialog returns and re-opens prefilled | `demos/README.md:3-15` |
| `confirm.html` | `{answer:true}` with `feedbackText` travelling beside it, not replacing it | `demos/confirm.html:46-50` |
| `pick.html` | one-of-N; a typed "somewhere else" is the answer, never "Other" | `demos/README.md:20` |
| `text.html` | free text; empty ≠ cancelled | `demos/text.html:41` |
| `form.html` | wizard: id→answer map + `completedCount`, `multi` array, hidden field | `demos/form.html:111-119` |
| `aloud.html` | everything rendered from the one `id="deckhand-aloud"` JSON block, a talk mark per card | `demos/aloud.html:30`, `:70` |
| `tweak.html` | sliders → `{answer, action:"agent"}` — never `"file"`, there is no file lane on a phone | `demos/tweak.html:85-88` |
| `demos/check.py` | per page: tags balance (VOID exempt), a non-empty `<title>` (it is where the slip's name comes from), the literal `window.deckhand.respond`, and none of `http:// https:// fetch( <form <link <iframe <script src XMLHttpRequest @import` — because a page reaching out fails **silently** under the CSP | `demos/check.py:15-21`, `:66-79` |
| UI tests | four, need a running daemon plus `DECKHAND_TOKEN`/`DECKHAND_HOST`: open a session and reach the talk mark (surviving paging), holding a row talks rather than opens, the connection is always stated (ON/WAIT/ERR/OFF), starring turns a session into a landscape deck column | `UITests/DeckLoopTests.swift:12`, `:39`, `:50`, `:59` |
| Build config | iOS **18.0**, Swift 6.2, bundle `dev.jurrejan.deckhand` (explicit — push cannot go on a wildcard App ID), team KA6433FU8U, iPhone only, `NSSupportsLiveActivities`, mic + local-network strings, `NSBonjourServices _http._tcp`; widgets extension `…deckhand.widgets` | `project.yml:5`, `:37`, `:49-64`, `:65-86` |
| Sources exclude `**/CLAUDE.md` | two would both flatten to `Deckhand.app/CLAUDE.md` and fail the build | `project.yml:15-19` |
| SwiftPM | one product `DeckhandKit`; targets `DeckhandKit`, `IconMaker` (macOS-only executable), `DeckhandKitTests` with a copied `Fixtures` folder | `Package.swift:11-22` |
| Entitlement | `aps-environment: development` only | `deckhand/Deckhand.entitlements:5-9` |

### 17.4 Tests

Daemon (pytest, `daemon/tests/`) — `test_api.py` (health open, everything else gated; panes; turns; audio kept with utt off; focus; route named; images fenced to their own session; briefings with no model; reading a summary bumps the queue) · `test_briefings.py` (what is owed a briefing and in what order, survival across restart) · `test_context.py` (context fullness off the last request, week spend) · `test_deliver.py` (route-as-authority: pane typing, socket fallback, `keyboard` never falling back, the peer frame and auth line) · `test_files.py` · `test_nudge.py` (asked once, by name, with a cooldown) · `test_plugin.py` (manifest identity, nothing dangerous in the menu bar, revision caching) · `test_prompts.py` (every prompt loads; an unfilled placeholder would have reached a live session) · `test_push.py` · `test_sessions.py` (only pids `ps` shows; sessions survive iTerm being unavailable) · `test_skill_scripts.py` (both skill scripts as a session runs them, through `demos/check.py`) · `test_summarize.py` (empty activity never reaches the model; exactly three task tools) · `test_tasks.py` · `test_transcribe.py` (the utt lane, silence gives up rather than hanging) · `artifacts/` (the three endpoints, traversal and symlink escapes refused, `.gitignore` seeded, size ceiling) · `filters/` (chain semantics, crafting's floor and every model failure, the two endpoints) · `projects/` (source precedence, other machines never rows, trust and numbered collisions) · `reading/` (inbox, commands, context tree, raw lines, turn reading and paging) · `settings/` (round-trip, resolution on the Mac, allowlist, unreadable file).

Swift (`swift test`, `Tests/DeckhandKitTests/`) — `ArtifactTests` (the wire and the injection that is the whole security boundary, with no web view so it runs in milliseconds) · `ArtifactStyleTests` · `ClientTests` + `Wire/ClientTests+Turns` + `ProjectTests` (serialized, split to stay under the 300-line gate) · `Clips/ClipArchiveTests` (mostly the failure side) · `ControlTests` · `FadeTests` · `FittingTests` · `GroupingTests` · `FilterTests` (a value the phone has no type for goes out as it came in) · `ListingTests` · `MarkdownTests` · `ProseTests` · `MarkupTests` · `QuotingTests` · `ServerSettingsTests` · `UnderneathTests`.

---

## 18. Corrections to `.orchestrate/capabilities.md`

Ordered by how much they change what an agent would do.

1. **Per-project settings UI now exists** — §4 Gaps says "no per-project config screen exists yet in the app". `deckhand/Views/Projects/ProjectSettingsView.swift` ships all seven keys with an "only here" marker, a "Follow the Mac for everything here" reset and the sessions running in that folder, reached from a project row's context menu (`Views/Projects/ProjectListView.swift:135-139`) and from the session menu (`Views/Session/SessionHead.swift:132`). The global screen exposes all seven too (`Views/SettingsView.swift:76-95`). **No settings gap remains.**
2. **`GET /sessions/{id}/turns` bounds are wrong** — the doc says `limit` 1–50. Actual: `limit` 1–200 default 8, plus a `before` cursor (≥0) that counts backwards from the tail, and the response carries `more`; `queued` only appears on page 0 (`D/app.py:165-187`).
3. **There is no `POST /sessions/{id}/artifacts`** — the doc's wire summary (inherited from the root CLAUDE.md's `GET|POST /sessions/{id}/artifacts`) is wrong. The only artifact POST is `…/{aid}/answer` (`D/artifacts.py:258-289`). A session writes a slip by writing the file, never over HTTP.
4. **`POST /sessions/{id}/audio` answers 201, not 200**, and its response also carries `received_at` (`D/saying.py:58`).
5. **The `skills/deckhand/` skill is missing from the doc entirely** — it is the agent-facing surface the doc's §2 hand-writes in prose: `SKILL.md`, `reference/wire.md`, `reference/traps.md`, `scripts/slip.py`, `scripts/answer.py`, and `templates/` as symlinks into `demos/`, gated by `daemon/tests/test_skill_scripts.py`. It is symlinked at `~/.claude/skills/deckhand` on this Mac (verified) although no `just` recipe creates that link.
6. **Filter facts to sharpen** — the `craft` filter's settings are `target` (default `opus-5`) and `floor` (default 12), and it reads its whole run config from `prompts/crafting.md` frontmatter (`D/filters/crafting.py:31-36`, `:109-132`). The doc says `words` is "typically first in the chain"; nothing in code orders them — order is purely the array's (`D/filters/config.py:3-5`).
7. **Task tool names confirmed** (the doc marks them subagent-sourced and unverified): `add_task`, `set_task_state`, `drop_task`, bound as `mcp__tasks__*`, `MAX_KEPT=200`, `MAX_TEXT=120` (`D/tasks.py:24-35`, `:125-153`).
8. **Nudge constants confirmed and named**: `POLL=30 s`, `SETTLE=120 s`, `AGAIN=30 min`, killed Mac-wide by `DECKHAND_NUDGE` ∈ `0/false/no` (`D/nudge.py:24-42`). Both guards are in memory only, so a restart can re-ask inside `AGAIN` (`D/nudge.py:33-35`).
9. **`PUT /settings` never 400s** — the doc says an unoffered model "is refused rather than passed through", which is right in effect but not in mechanism: it is coerced to `None` and falls back, and the response is the stored document read back (`D/settings/wants.py:99-120`, `:185-197`).
10. **`GET /projects` `source` values** are `file` / `atlas` / `atlas-cache` / `none` — the doc writes "a plain file" for the first (`D/projects/routes.py:26`, `D/projects/sources.py:114-133`).
11. **`menubar/` confirmed dead** (the doc's §4 already says so): only an untracked `Info.plist`, no Swift, no `project.yml` target, no repo reference.
12. **`prompts/CLAUDE.md` exists** — the doc's §4 asks for it to be written. It is there and states the loader contract (`D/prompts/CLAUDE.md:19-21`).
13. **Two facts the doc lists as "subagent-verified, spot-check" are now confirmed**: the Live Activity content-state is `waiting`, `line`, `name`, `when` — **not `moment`**; `moment` is a computed `Date` on the Swift side (`Sources/DeckhandKit/LiveActivity.swift:14-34`). The two DeckhandKit decode traps are real: `literally` on filters, `plain` on settings (`DeckhandClient+Filters.swift:43`, `+Settings.swift:30`).
14. **Security finding, not in the doc**: `/docs`, `/redoc` and `/openapi.json` answer **without a token** — `FastAPI(...)` is constructed with no `docs_url`/`openapi_url` override (`D/app.py:51`; no match for `docs_url|openapi_url|redoc` anywhere in `daemon/src`), so the full route and body schema is readable by anything on the LAN. Every other route is gated.

---

## 19. Present but incomplete

Each verified by grep for callers, not inferred.

1. **The `subagents` setting has no consumer.** Stored, served, resolved, exposed on both settings screens and documented as "let the summariser read what this folder's subagents did" — but `summarize.py`'s only `wants.resolved` call reads `summary_model` (`D/summarize.py:117`). Repo-wide, `subagents` appears only in `D/settings/wants.py:56,58,70,150,174`, `Sources/DeckhandKit/Settings/Wants.swift` and the two settings views. Flipping it changes nothing today.
2. **`POST /notify` reports success it cannot know.** Once the folder's `called` gate passes, `push.called` returns `None` regardless of what APNs did, so the route answers `{"pushed": true}` even when the send failed (`D/push.py:253-258` vs `D/app.py:314-316`). Every sweep failure is likewise log-only (`D/push.py:278-279`).
3. **Upload and transcribe disagree on suffixes.** `saying.AUDIO_SUFFIXES` admits `.aac .mp4 .ogg .webm`; `transcribe.AUDIO_SUFFIXES` does not (`D/saying.py:31` vs `D/transcribe.py:27`). Such a clip passes the 415 gate, is stored under `audio/<sid>/`, and returns 201 with `transcript_error: "utt cannot open .webm files"` — permanently untranscribable and never cleaned up. Conversely `.aiff` transcribes but 415s at upload.
4. **Nothing prunes `audio/` or `images/`.** The only unlink in the whole daemon is `transcribe._clean` on the utt job copy (`D/transcribe.py:86`); `grep -rnE 'unlink|rmtree|shutil' daemon/src --include='*.py'` returns that one line.
5. **Briefing cost is process-local.** `summarize._spent` resets on every daemon restart (`D/summarize.py:42`) while `briefings/<sid>.json` survives, so `spent` and the briefing it describes can disagree.
6. **`Prompt.route`, `.images` and `.source` are populated and never read.** Set at `D/saying.py:53-55`; no shipped filter consumes them. Deliberate contract surface (`D/filters/kinds.py:29-31`), but untested against a real filter — as is `Field.kind = "bool"`, which has no instance anywhere (`D/filters/kinds.py:74`).
7. **`LiveUpdates.running` and `.trouble` are write-only.** Set at `deckhand/LiveUpdates.swift:16-17,26,53,58,79,81`; the `live` instance is only referenced at `App.swift:8,25`, so "Live Activities are switched off for Deckhand" and "the Mac did not take the token" can never reach a screen.
8. **`Switchboard.saving` is write-only** (`deckhand/Wanting.swift:54-55`) — the per-folder write spinner it was built for is never drawn; `ProjectSettingsView` draws only `wants.failed`.
9. **`Settings.resolved(for:)` duplicates `GET /settings/project`**, which no client method calls (`Sources/DeckhandKit/Settings/Wants.swift:124`) — two answers to one question. Related: `Settings.encode` writes `projects` but not `offers` (`:114`), so a round-tripped `Settings` loses its offers.
10. **Unused design surface**: `PageHeader` is never instantiated (`Design/Chrome.swift:96`), `Typography.lead` has zero references (`Design/Typography.swift:9`), `Radius.extraLarge` and `Radius.pill` likewise (`Design/Spacing.swift:18-19`) though the CSS mirror still defines them (`Artifacts/ArtifactTokens.swift:45`). `RunState.online`/`.off` reach a screen only via the connection pill (`deckhand/Model.swift:26-33`).
11. **Dead Swift**: `TalkGesture.pressed` has no reference (`Views/TalkControl.swift:238-241`). `ReachGesture` is named in two doc comments and `deckhand/CLAUDE.md:42` but no such symbol exists — the type is `TalkGesture` with a `reach` closure. A dangling doc comment sits above nothing in `Views/Talk/TalkMark.swift:21-22`.
12. **`config.TOKEN_HEADER` is dead** (`D/config.py:16`) — the header name is carried only by the FastAPI parameter name at `D/app.py:34`.
13. **`briefings._queue()` duplicates `_next()`'s walk** (`D/briefings.py:120-124` vs `:127-142`); `_queue` exists only to compute `stale` in `of()`, and both re-list sessions and re-`stat` every transcript per call.
14. **`filters.path` is an unused export** (`D/filters/__init__.py:13,26`) — only tests reach it, and they go through `config.path()`.
15. **`docs/agent-surface.md` is partly shipped**: phases 1–2 exist exactly as specced (`:106-114`). Not shipped — `just install-skill` (`:72`, `:258`, no match in the Justfile), the agent token that would make the skill's four refusals real (`:245-248`, no `agent_token` anywhere in `daemon/` or the Swift trees), the MCP server (`:149-185`, no `mcp*.py`, and `daemon/pyproject.toml:17-18` declares only `deckhand-daemon`). The doc's own "a plan, not a build" (`:3`) is now stale.
16. **`docs/control-surface.md` is a proposal, nothing shipped**: no `Command`/`Reply` façade, no `Route`, no `Snapshot`; `AppModel.current` is still the plain mirror the doc describes (`deckhand/Model.swift:66`); no `AppIntent`, `CFBundleURLTypes` or `onOpenURL` in `deckhand/`, `widgets/`, `Sources/` or `project.yml` — the app has no command interface of any kind.
17. **`project.yml` declares `DeckhandWidgets` twice**, byte-identical (`:65-86` and `:87-108`). A YAML duplicate key: the last silently wins, so an edit to the first block does nothing.
18. **`agent.md` is stale in three ways**: iOS deployment target "26.0" (`agent.md:8`) against 18.0 in `project.yml:5`; its `just check` summary omits `daemon-lint`, `daemon-test` and `demo-check` (`agent.md:14`, `:51`); its project tree shows only the SwiftUI app, no `daemon/`, `Sources/` or `widgets/` (`:29-34`). Already filed P1 at `docs/prompt-review.md:34`.
19. **Outside the quality gate**: `widgets/*.swift` and `skills/**/*.py` are in no `.quality.json` glob (`.quality.json:10-16`), so neither is LOC- or directory-capped (SwiftLint's own file_length still catches the widget). `just ui-test` and `just icon` are in no gate, so nothing verifies the committed `icon.png` still matches `DotGlyph.anchor`.
20. **`reading/CLAUDE.md:8` misattributes context fullness** to `transcripts.py`; `last_request` and `context_window` live in `D/sessions.py:234-279`. The invariants written there are correct — only the file is wrong.
