# deckhand — session history

Everything below comes from the Claude Code transcripts on this Mac, read field by field, never
whole. The spine is what the person himself typed or dictated: 92 asks across ten sessions,
09-09 13:08 to 09-10 15:41 local (CEST). Git says 143 commits on `develop` over the same two
days, plus one `deploy: initial public snapshot` (`6c20d19`) on a worktree branch.

Sibling documents: [../CHANGELOG.md](../CHANGELOG.md) is what landed, [features.md](features.md)
is what the thing can do today.

A note on one word: the glossary reserves **ask** for an item on the person's list that the Mac
keeps. Here it means one thing JJ asked a session for, because that is what this document is a
list of. Where the list-item sense is meant it says *list item*.

**A correction to the brief.** The largest part of this history is not in
`~/.claude/projects/-Users-jurrejan-dev-multi-stack-deckhand/`. The session that built deckhand
from nothing was started in `~/dev`, so its transcript lives in
`~/.claude/projects/-Users-jurrejan-dev/333a1f7c-43af-42ff-bf8b-46952ad86697.jsonl` — 51 MB,
26,900 lines, 58 of the 92 asks, and 42 subagent sidechain files beside it. Without it the
history has a hole from 13:08 to 23:49 on 09-09, which is most of the app.

The second correction: the 2,441 files in `-Users-jurrejan-dev-multi-stack-deckhand-daemon/`
(119 MB) are **not** human sessions and not sidechains. They are the daemon's own Claude Agent
SDK runs — every briefing and every idle check it has written, for every session on this Mac.
Their prompts are `<task_list>` and `THE LIST SO FAR`, and they carry other projects' work
(utt, framelink, a French filter quiz). One ask each, none of them JJ's. They are evidence of
volume, not of intent.

## 1. The sessions

| id | start | end | duration | asks | size | what it was about |
|---|---|---|---|---|---|---|
| `333a1f7c` *(cwd `~/dev`)* | 09-09 13:08 | 09-10 04:01 | 14h 53m | 58 | 51.3 MB / 26,900 lines | The build. Daemon, app, the utt lane, delivery routes, Live Activity, filters, slips, picture markup. Five compactions. |
| `fe2a158d` | 09-09 17:41 | 09-09 17:52 | 11m | 1 | 0.98 MB | Scan the tree for PII, then create the public remote. |
| `e9f56c38` | 09-10 01:49 | 09-10 03:43 | 1h 54m | 4 | 0.76 MB | Open every prompt file in Zed; then materialise the APNs key out of 1Password until push worked. |
| `1e1df880` *(cwd `daemon/src/deckhand_daemon`)* | 09-10 02:02 | 09-10 02:03 | 2m | 1 | 0.26 MB | Rewrite the crafting filter's prompt. |
| `1f1fb898` *(same cwd)* | 09-10 02:13 | 09-10 02:16 | 3m | 2 | 0.40 MB | Frame the summariser's user prompt in named tags; then `deliver.py` too. |
| `fc006ecc` | 09-10 02:17 | 09-10 02:20 | 4m | 2 | 0.18 MB | `/prompt-crafter` over every prompt — a false start, reopened seconds later as `a255f385`. |
| `a255f385` | 09-10 02:21 | 09-10 06:17 | 3h 56m | 2 | 1.82 MB | The prompt audit that stuck: every prompt out of Python and into `prompts/*.md`. Seven peer messages with the daemon's own session about restarts and unexplained commits. |
| `3f91172f` | 09-10 05:09 | 09-10 15:41 *(live)* | 10h 32m | 20 | 15.1 MB / 7,250 lines | Projects and atlas, slips answered aloud, triggers and per-project settings, the header and layout pass, the clip archive. Two compactions. |
| `16a23c5d` | 09-10 05:10 | 09-10 05:23 | 13m | 1 | 0.97 MB | `/claude-md-tree` — split CLAUDE.md into a root map and nine context packets. |
| `6089e791` | 09-10 15:36 | *(live)* | — | 1 | 0.53 MB | This analysis. |

Plus **2,441 daemon SDK sessions**, 119 MB, 09-09 15:02 → 09-10 15:43 — one per briefing or
idle check the Mac wrote, across every project, not only this one.

Three sessions ran at once for most of 09-10 02:00–06:00: `333a1f7c` on the app, `a255f385` on
the prompts, `e9f56c38` on push. They talked to each other over the peer socket rather than
through JJ.

## 2. The timeline

Times are local. `§` marks an item that is a status report or a paste rather than a request.
Quotation marks are verbatim; everything unquoted is tightened. Dictated asks keep their
mistranscriptions where they are telling.

### 09-09 — afternoon: make it exist

1. **13:10** `333a1f7c` — `/go`: "Build a Swift application for iOS that talks to a daemon or
   server on my MacBook. The MacBook will communicate what iTerm windows with Claude are
   currently open and the app on iOS will show me an interface where I can switch between the
   sessions. Then the iOS app allows me to uh speak to each of those sessions and we will
   handle the transcription of my speech on the MacBook that is a phase two. For now I want you
   to make sure that communication between the app and the server works so that the uh
   transcription samples are available on the MacBook. The iOS app will also have to display
   like the last couple rounds slash messages of the uh cloud session." Plus the aside that
   decided the name of nothing and the spelling of everything: "(cloud == claude STT)".
2. **14:12** § A screenshot from the LAN: `https://trash.jurrejan.com/#now` unreachable.
3. **14:19** "I want to install it to connected iPhone".
4. **14:35** § "connected, no live session".
5. **14:36** § "just sent 33kb of speech".
6. **14:39** "USE ONENEV deckhand.UTT_SECRET" — the secret goes through onenv, not a file.
7. **15:39** "The summarizing is timing out i think".
8. **15:57** "stop crying about the api. Let the user choose the route in which they want the
   message to be routed."
9. **16:06** § "i had set it to socket, yet it looks like this" + screenshot.
10. **16:30** "continue" (after `/login`).
11. **16:51** "Create app icon".
12. **17:10** "You are still using the API route? nothing is provided for this part?"
13. **17:11** "Write a report that i can hand over to utt."
14. **17:13** "i dont need sa design, just a simple md file with your findings."
15. **17:52** `fe2a158d` — check on the pii-scan agent and continue the public-remote task:
    report findings and confirm before creating any public remote.
16. **17:55** "We no longer need our system tray."
17. **18:18** § utt 1.1.0 is released and installed — the full release report pasted in, down to
    which bead is still open.
18. **18:42** "install deckhand to iphone 17 too".
19. **18:45** "Scan app for compatibility with the App Store."
20. **18:56** "Anything that does not change the app significantly, do it now."

### 09-09 — evening: the Lock Screen, then reading a session properly

21. **19:01** "I want you to explore using the IOS live view for showing the user at all times
    if any updates on the terminals that came in."
22. **19:08** "Yep, do whatever's necessary to reach the goals."
23. **19:22** "Use fucking normal language just ask me what you want to ask."
24. **19:25** § "The iPhone twelve is now unlocked."
25. **19:31** "The iPhone cannot go to sleep while the transcription is on."
26. **19:40** The summary page needs more spatial contrast; the whole session detail view loses
    space to the back button and the title under it. "So we need to make this a little bit
    smarter."
27. **20:07** "Is it possible to tap into the recap feature that Claude Code already has itself
    and is already spending tokens on?"
28. **20:09** Not all the one-line briefings fit the UI. "Make sure that the UI is more
    forgiving than the assignment that we give to the sub agent."
29. **20:41** The files tab works, but it cannot show an MP4. Why?
30. **21:01** Images open at huge dimensions. "They need to scale to the window that they're in,
    and you need to be able to zoom in and out."
31. **21:12** "I also need to be able to rename sessions."
32. **21:26** On the landscape deck, make it a long press rather than tap-to-record — "I'm not
    saying I want Hold to record because that is a global setting that you can change" — and
    put the same long press on the portrait overview.
33. **21:49** "I want to be able to tell agents to make certain tool calls background
    progresses by some UI that sits under the latest tool call."
34. **21:55** Ending a run works; now flip it — let him force a prompt sitting in the inbox and
    not yet picked up. And a prompt he just added to the inbox disappeared.
35. **22:10** "You added a background behind the transcript button that is super wide and
    available and visible at all times… It should just be the one button in the center that is
    always visible."
36. **22:22** Let him attach images to the transcript before sending — from the clipboard or
    from Photos.
37. **22:35** The same three prompts now say "picked up while it was working". "Still, I have no
    idea what this means. It's very unclear."
38. **22:52** § Screenshot: prompts that look unprocessed. "or maybe they are, I'm not sure."
39. **23:01** "Install new version of the app on my iPhone."
40. **23:02** Make it clearer where the session has got to in the transcript — the "working on
    it" label is not always visible because it may be in tool calls. "So let's have like an
    active line or something."
41. **23:15** "Okay, I still see three prompts here that look like they have not been processed.
    This needs to be fixed." + screenshot.
42. **23:37** Review everything the summariser does, state and transcript and the list it keeps.
    Cycle every project efficiently; when he opens a project it goes to the top of the queue;
    on a cold start or reinstall every project shows its last briefing at once; a session with
    no activity is not refreshed at all.
43. **23:59** Group files by extension. Open an image and annotate it, comment on it more than
    once, point at a coordinate and attach a prompt to that point — "and that way I can
    basically give feedback on everything on one image. launchd an Opus subagent to analyze
    this request, fill in any gaps, ask any questions, and then build it with sub agents."

### 09-10 — after midnight: slips, filters, prompts

44. **00:02** Markdown files in the files tab need a switch between raw and formatted.
45. **00:17** `/go`: subagents to design a per-project section that is "a HTML viewer without
    any addressbar or anything that looks like a browser, it just shows 1 page. That page is
    built like Claude also makes artifacts… a very basic way of relaying answers back to the
    project agent… Agents can access and reuse earlier artifacts and edit, improve, duplicate
    them. Create the framework, the harness and implement demo artifacts that do what consult
    user does."
46. **00:26** `/go`: "As one of the filters, create the lightest possible sonnet claude agent
    sdk setup that can run the prompt-crafter skill."
47. **00:35** "The filters that were added, they need to be configurable per terminal per
    project, not globally."
48. **01:06** "I do not see a pages tab in my application."
49. **01:10** The pages tab looks great. Can existing pages be updated? Are all six actually
    relevant to this session — which are the daemon's and which are real?
50. **01:22** § Answered the artifact `how-pages-work` from the phone: `"read"`.
51. **01:22** Seven pages, all answered, but the status does not say so — "it looks like they
    might still need an answer, even though it says answered".
52. **01:26** "The order is wrong. The order of the menu at the bottom of the project, it should
    be summary, pages, transcript and at the end files."
53. **01:27** On the review card, attach several images in one go, and give them the same
    tap-a-point feedback that files already have.
54. **01:33** Comments on an image have to be spoken, not typed. "I don't want to write them. I
    want to use the transcription feature… Maybe it needs to be handled in a pop up. I'm not
    entirely sure."
55. **01:36** In the daemon's own page the cards row and the tasks row sit too close and read as
    busy. Give each its own line, more height, and make the pair read as one thing.
56. **01:41** "The shape of the Tudu blocks around the entire app need to be much neater…
    Things need to be like exact and tight." (*Tudu* = todo.)
57. **01:49** `e9f56c38` — "Open all files with prompts in Zed".
58. **01:51** — scope for 57: "All prompts that are used with claude agent sdk or prompts that
    are used to speak to active agent".
59. **01:55** § Answered the artifact `footer-and-naming` from the phone. Three decisions in one
    answer: notifications keyed to a push **key**; the thing on the phone is called **slips**;
    and "I am still unable to put a transcription in this input field by the way. Create a page
    for me or a slip where you explain how to walk through all the steps for the
    notifications."
60. **02:02** `1e1df880` — "Rewrite the poorly written and vague prompt in this file"
    (`filters/crafting.py`).
61. **02:13** `1f1fb898` — "Optimize the framing of the user prompt using /prompt-crafter xml
    patterns".
62. **02:16** — "what about this file?" (`deliver.py`).
63. **02:20** `fc006ecc` — `/prompt-crafter`: "Review all prompts and presentation of prompts or
    delivery of prompts and measure optimize them for the context they will be used in."
64. **02:20** § Pasted back the review of the prompt-crafter skill itself — four changes, review
    output proportional, contradictory verification rules, forced evidence of editing, and
    permission rules that should respect existing authorisation.
65. **02:21** `a255f385` — the same `/prompt-crafter` ask, in the session that carried it out.
66. **02:28** "Separate all prompts from python files. Have one folder with markdown files and
    frontmatter for the key settings for these. Use anthropic agents kind of format."
67. **03:16** "I need to be able to send slash commands such as exit. I think exit is best fit
    under the three dots menu, accessing holder skills is probably something to do in the
    prompt previewer." (*holder skills* ≈ folder/other skills — uncertain.)
68. **03:35** § `e9f56c38` — pasted the onenv key list, `AUTHKEY_U76TN79743_P8` and
    `UTT_SECRET`.
69. **03:40** § "works".
70. **03:41** § Answered the slip `push-key` from the phone: `"done"`.

### 09-10 — morning: projects, atlas, and a slip you can talk to

71. **05:10** `3f91172f` — `/go`: "Implement a universal consumer of a project list but create a
    first-class integration with /atlas-cli this needs to enable the user to start a session in
    any project's work dir."
72. **05:10** `16a23c5d` — `/claude-md-tree`, no arguments.
73. **05:44** "Test files are excluded." (Correcting a size-cap reading.)
74. **05:44** "Alright, let's go, install this app for me."

*(Gap, 05:44 → 13:18. No asks, no commits.)*

75. **13:18** "Create a special slips card that is fully aimed towards verbal responses. So I
    want it to be like for each question there will be a card and with a big record button that
    looks the same as the button that we have in the application. Maybe there's an HTML
    representation that we can dynamically replace with the SwiftUI version. Have a think about
    how we can properly integrate that without it feeling like it's botched on."
76. **13:31** "Write me a small slip. Don't spend a lot of time nor tokens. And then to explain
    me how you built the answering slip that you just sent."
77–80. **13:40–13:41** § Four near-identical deliveries of the answer to the slip
    `open-questions` — six questions answered aloud. The two that carry new work: more room per
    project row so some of the description shows, and editing a project's details straight into
    atlas from the session's config page; all models default to the Claude defaults; and an
    optional toggle letting the summariser read subagent transcripts and summarise each one.
81. **13:41** "In the most recent slip, the send all six answers button at the bottom did not
    function. I had to close it out using the cross using the x." (Which is why 77–80 arrived
    four times.)
82. **14:03** "I want to improve this page layout a little bit, organizing information a little
    bit more structured and Designed, I guess." + screenshot.
83. **14:31** "The models are not labeled so I don't know what I'm changing." + screenshot.
84. **14:35** "Under files, I want you to make a special category for the clot MD files, and I
    want you to draw them in a tree like we do with Atlas tree." (*clot MD* = CLAUDE.md.)
85. **14:55** Swiping between a session's sections needs an indication of where you land — "some
    overlay swipes in and out. Should be subtle." Clean the header: no back arrow, no icon, the
    context bar much smaller, "it could potentially be a circle, make it a small circle that
    fills up busy versus idle", placed under the project header. And split up what is in the
    top-right menu.
86. **14:59** The content containers on the session page do not use the full height — the bottom
    of the screen is unused.
87. **15:05** Layout feedback marked on a picture: add a transparency gradient mask; move this
    down a little. Sent with both copies, marked and unmarked.
88. **15:13** "Allow to open thinking blocks in the transcript view. Either real time or
    previous thinking blogs."
89. **15:24** "The transcription button now has the hold feature, but it no longer works on tap
    now. Additionally, it constantly shows the hold for clips instruction. It shouldn't be
    there."
90. **15:30** "Start a subagent to build the agent surface."
91. **15:37** `6089e791` — "I'm not entirely sure but I think we did this today already. I want a
    full analysis of the session history of this project and I want to create a change log and
    an exhaustive list of all the features that we have created."
92. **15:41** "Run a sub agent to build the following feature, mostly a visual feature. When
    agents are sending messages to other agents, I want to see… whether that is another active
    and in view or not hidden session in deckhand… I want that visualized… on the overview
    page, I want to see sort of like a futuristic link between the two. It could be like an
    effect of like glowing particles moving from one direction to another based on who sent a
    message to who… And it should work with sort of like a timer or threshold. So if they
    communicated in the last, let's say five minutes, then I want to see those visualizations.
    And the longer it's been, the less intense they get. And I want that five minute timer… in
    the settings."

## 3. Decisions and reversals

**The route became a setting instead of an argument.** Ask 8 is the pivot: "stop crying about
the api. Let the user choose the route in which they want the message to be routed." The
session had been defending a transport choice; JJ made it a user-facing one — Auto, Keyboard,
Socket — and the phone now says which one took each message. Asks 9 and 12 chase the same
thing twice more ("i had set it to socket, yet it looks like this"; "You are still using the
API route?"). The invariant in CLAUDE.md — the route is an authority choice, not a transport
choice — is the settled form of this argument.

**No design treatment on a findings document.** Ask 13 asked for a report to hand to utt; the
session opened the design-lead artifact skill; ask 14: "i dont need sa design, just a simple md
file with your findings." What shipped is `.claude/tickets/utt-plugin-report.md`.

**The menu bar app was deleted, not improved.** Ask 16: "We no longer need our system tray."
Commit `781c153 refactor: delete the menu bar app, utt's page replaced it`, 20 minutes later.
The `menubar/` folder survives as an empty shell. CLAUDE.md records the reasoning in one line:
"There was a menu bar app; the plugin page replaced every reason it existed."

**Ask plainly.** Ask 23: "Use fucking normal language just ask me what you want to ask." Aimed
at a session asking a design question in its own vocabulary rather than his.

**Long press, and explicitly not hold-to-record.** Ask 32 draws the distinction itself — hold
is a global setting he can change, the long press is the trigger for tap-to-record. This one
came back as a regression: ask 89, "it no longer works on tap now", fixed in `0103784 fix: give
tap-to-talk its tap back`.

**Filters are per terminal, not per Mac.** Ask 47 reversed what had just been built globally.
Commit `002dea1 scope: a filter chain belongs to a terminal, not to the Mac`, and the chain is
keyed by session *name* rather than id so it survives a restart.

**Comments on a picture are spoken, not typed.** Ask 54 rejected the text field that ask 43 had
produced: "I don't want to write them. I want to use the transcription feature." Answered twice
over — `bc971f5 say: speak into any field instead of typing into it`, then `c7ec08c feat: the
controls come to the hotspot, and there is no field`.

**The tab order was wrong and he said what right was.** Ask 52 — summary, pages, transcript,
files — commit `7da0397 tabs: summary, pages, transcript, files`.

**One button, not a background.** Ask 35 undid a chrome addition: "Don't… that shouldn't be
there. It should just be the one button in the center."

**"Pages" became "slips".** Ask 59, answered through the app itself. The glossary now fixes the
split: say *slip* to a person, write *artifact* in code and on the wire.

**Every prompt is a file.** Ask 66: "Separate all prompts from python files. Have one folder
with markdown files and frontmatter… Use anthropic agents kind of format." This is now a global
invariant. Two narrower asks (60, 61) had already rewritten individual prompts in place; 66
moved them out of Python entirely.

**Claude Code's own recap was investigated and mostly declined.** Ask 27 asked whether the
existing recap could be reused. The session checked rather than assumed, and reported back that
`ai-title` is never written for named sessions (and all of JJ's are named), `last-prompt` is raw
activity rather than a recap, and only the compaction summaries are genuinely rich. The
briefing stayed the daemon's own, and the schedule moved to the Mac — `32e6a86 perf: the Mac
owns the briefing cycle, and a quiet session costs nothing`, which is ask 42 delivered.

**A correction JJ made to a check, not to a feature.** Ask 73, "Test files are excluded." —
about how the size cap was being read.

## 4. Abandoned, deferred, or still in flight

Cross-checked against `.orchestrate/queue.md`, `.claude/tickets/todo.md`, and git.

**Still open, named as such in `.orchestrate/queue.md`:**

- **Subagents made visible** (ask 33, and the subagent toggle in the answer to 77–80). The
  switch is on the project page and reaches the daemon; `summarize.py` does not yet read
  `subagents/agent-*.jsonl`. Recon found why it is delicate — one session here is 706 MB across
  23 files. Marked *PART DONE*.
- **Editing a project's details straight into atlas** from the config page (from the slip answer
  at 77–80). Needs a daemon proxy; the phone must not reach atlas directly.
- **Mermaid inside a slip.** The renderer draws in transcripts and briefings (`0312c54`,
  `7265ad0`) but an artifact page is sandboxed by its own CSP.

**In flight at the moment of capture (15:30–15:41, after the last commit):**

- **The agent surface** (ask 90). `docs/agent-surface.md` is committed (`6e4e7a0`); phases 1–2
  exist on disk as `skills/deckhand/` with SKILL.md, `reference/wire.md`,
  `reference/traps.md`, two scripts and three templates. The agent journal shows the intent
  still open at 15:32. The MCP server the plan designs is deliberately phased fourth and has a
  named trigger — build it only when transcripts show a session that needed the person, had the
  skill in context, and decided alone.
- **Peer-message visualisation** (ask 92) — the glowing link between two sessions on the
  overview, with a settable five-minute threshold. Asked at 15:41, after the final commit.
  Nothing of it exists yet.
- **Clip telemetry and an audio bench** — agents `telemetry`, `audio-bench`, `clip-vault`. The
  clip archive landed (`dd3f81f`); the bench was still queueing ~250 transcription jobs through
  utt at 15:39 per the journal.

**Deferred in `.claude/tickets/todo.md`, still unticked:**

- **Guard against pid reuse before delivering.** The key file carries `procStart`, which is how
  Claude Code itself avoids messaging a recycled pid; `deliver()` does not check it.
- **A column scrolls now that a press has to settle, but the two gestures still share a
  surface.** Left as something to watch in real use. Asks 32 and 89 are both this gesture.
- **Route per session rather than globally** — written as Next, and superseded in practice:
  filters went per-session (`002dea1`) and the route became a setting, but the line is not
  ticked.

**Asked and apparently not built:**

- **An MP4 in the files tab** (ask 29). The answer was a diagnosis — `f691555 fix: a video was
  refused by the upload cap` addresses the upload, not playback. Uncertain whether video now
  plays; no commit says it does.
- **App Store submission** (asks 19, 20). Only the part that changes nothing shipped —
  `38908eb fix: the four App Store blockers that do not change the app` — by JJ's own
  instruction. The rest is untouched, and `skills/app-store-preflight` was never run again.
- **"Update existing pages"** (ask 49, a question rather than an instruction). Answering and
  reading back landed (`ddd9f61`, `94c53fe`); an agent editing a page it already wrote is not
  recorded as done.

**Parked by the peer sessions, not by JJ:** three commits — `fb7e97c`, `2d4f5b6`, `b1e85d0` —
were made by something neither of the two concurrent sessions claimed, and one of them
(`fb7e97c`) broke `GET /sessions` for every request by committing a half-finished tree. It was
repaired in `8df2039`. The sessions compared notes over the socket and gave up on finding the
owner. Worth recording because the cause is still unidentified.

## 5. Working patterns

**Subagents, by name, constantly.** 31 named subagents across four sessions, every one
`general-purpose`: 15 from `333a1f7c` (summarizer, menubar, delivery, filters-daemon,
filters-phone, annotate, artifacts-daemon, artifacts-viewer, artifacts-demos, recording-tint,
pages-prominence, dictate-fields, card-pictures, page-selection, footer-stats), 12 from
`3f91172f` (trigger-audit, atlas-audit, subagent-recon, control-surface, capability-index,
utt-audit, mcp-plan, clip-vault, clip-vault-2, agent-surface, telemetry, audio-bench), 3 from
this session, 1 from `fe2a158d` (pii-scan). The naming is consistent and the fan-outs are wide:
ask 43 was answered by spawning an Opus analyst and then building with subagents, exactly as
asked. `SendMessage` was used 44 times in `333a1f7c` and 13 in `3f91172f` — agents were talked
to after spawning, not only collected.

**Checks were run, heavily.** Across the app sessions: `just check` 113 times, `just lint` 109,
`just test` 64, `just daemon-test` 37, `xcodebuild` 60, `just device` 27, `just ui-test` 18,
`just demo-check` 6 — against 132 `git commit` invocations. Close to one full gate per commit.
`.orchestrate/queue.md` records the gate result per feature with counts, not adjectives ("0 lint
in 112 files, 136 Swift tests in 23 suites, 260 pytest, 6 demo pages"), and names what was *not*
covered ("no UI test, and hold-to-talk on a card inside a ScrollView has not been exercised by a
thumb").

**The tool mix is overwhelmingly Bash.** 2,039 Bash calls in `333a1f7c` against 34 Write, 32
Read, 23 Edit; 550 Bash in `3f91172f`. Consistent with the repo's instruction to work through
the shell.

**Compaction was frequent and costly.** Seven `/compact` runs — five in `333a1f7c`, two in
`3f91172f`. Each one is a seam in the history: the ask before and the ask after are continuous
to JJ and not to the session.

**Handoffs went session-to-session over the socket, not through JJ.** `a255f385` and the
daemon's own session exchanged seven substantial peer messages between 02:37 and 06:16 —
negotiating a daemon restart against uncommitted work ("Reply with one word: safe — or wait"),
reporting the utt `plugins/` → `extensions/` rebrand and the four-minute window where dictation
was dead, and correcting each other's misattributions in writing. A framelink session replied to
a Deckhand idle check in the same channel. The most durable thing in those messages is a rule
neither session was asked for: never score a gate through a pipe, because a backgrounded
`just check-serial > log 2>&1; echo "EXIT=$?"` reports the echo's status and a failing run
arrived as exit 0.

**JJ used the app to build the app, from early on.** Eight asks arrived as slip answers from the
phone (50, 59, 70, 77–80, and the `push-key` answer), and many others are clearly dictated — the
mistranscriptions are the tell: *clot MD* for CLAUDE.md, *Tudu* for todo, *thinking blogs* for
thinking blocks, *cloud == claude* in the very first ask. Screenshots came from the phone
through Deckhand's own image lane (`~/Library/Application Support/Deckhand/images/<session>/`),
and by 15:05 they arrived marked up, in pairs, with the unmarked copy beside the marked one —
the feature from ask 43 used to ask for the next feature.

**The journal was used, unevenly.** 50 `agent-log` invocations. `recent` shows findings with
real evidence strings and three open intents, but also one handoff whose text is only "session
ended (prompt_input_exit)" — the protocol's own instruction to write a stopping point and a next
step was not always followed.

**The daemon's own model work dwarfs the human conversation in volume.** 2,441 SDK sessions in
25 hours — roughly one every 37 seconds — at 119 MB, against 72 MB for every session JJ actually
spoke in.

## Uncertain

- `3f91172f` and `6089e791` were still being written during this analysis; their end times and
  sizes are as of 15:41.
- "holder skills" in ask 67 is a transcription of something; folder, or other, is a guess.
- Whether MP4 playback in the files tab works now. No commit claims it.
- The owner of commits `fb7e97c`, `2d4f5b6` and `b1e85d0` is genuinely unknown, not merely
  unrecorded here.
- Asks 2–6, 9, 17, 24, 68 and 69 are status reports and pastes. They are counted in the 92
  because they are JJ's own words arriving in a session, but they are not requests.
