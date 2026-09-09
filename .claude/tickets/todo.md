# deckhand — open work

Ordered by what blocks the product from being what it is for: talking to a session from the
phone. Ticked items are verified, not just written.

## Done
- [x] Daemon lists live Claude sessions (`~/.claude/sessions/<pid>.json` + `ps` + `it2`)
- [x] Last rounds of a session on the phone, tool traffic filtered out
- [x] Hold to talk → clip lands on the Mac
- [x] utt transcribes the clip and the phone shows the text ("Testing one two." from the 12 Pro)
- [x] Connection state stated at all times; empty states say which empty they are
- [x] Favourites, hidden sessions, hold vs tap, landscape deck of columns
- [x] Summary of what a session did since you last spoke (Claude Agent SDK, sonnet, low effort)
- [x] One log file for Console.app; test runs stay out of it
- [x] Menu bar app: start, stop, restart, copy token, open log
- [x] Installed and running on the iPhone 12 Pro
- [x] **The transcript reaches the session as JJ's own words.** `it2 session run` types them
      into the pane and presses return, so they arrive as a prompt from the person at the
      machine. Proven end to end: a clip spoken on the phone appeared as a user turn in a live
      session with no peer framing. The peer socket (`messagingSocketPath`, auth line, `user`
      frame, `priority: "next"`) is the fallback when there is no pane.
- [x] **Panes work under launchd.** The plist asked for `ProcessType: Background`, which
      throttles the job so hard that a ~1 s `it2` call missed a 4 s timeout every time. Not an
      approval wall, as assumed all day. 9/9 sessions resolve a pane now.

## Next
- [ ] **Send-on-release vs confirm-before-send.** Today the transcript goes straight in on
      release. Speaking into a busy session is not undoable, so decide whether the phone should
      show the text for approval first — a toggle next to hold/tap is the obvious shape.
- [ ] The peer-socket fallback still arrives labelled as a message from another Claude session,
      carrying none of JJ's authority. That wrapper is a deliberate control and should not be
      defeated; the answer is to keep a pane available so the keyboard path is used. Watch how
      often the fallback actually fires.
- [ ] Guard against pid reuse before delivering. The key file carries `procStart`, which is how
      Claude Code itself avoids messaging a recycled pid; `deliver()` does not check it. Records
      are read fresh on every request today, so the window is small — it opens the moment
      anything caches them.

- [ ] Summary latency is ~30 s cold. Cache is per activity blob; consider summarising on the
      Mac's own schedule so the phone reads a ready answer.
- [ ] A column scrolls vertically now that a press has to settle before it records, but the
      two gestures still share a surface. Watch whether a slow, deliberate scroll ever starts
      a clip in real use.
