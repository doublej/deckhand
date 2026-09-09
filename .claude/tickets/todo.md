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
- [x] **The transcript reaches the session.** It goes into that session's own peer socket
      (`messagingSocketPath`), auth line first, as a `user` frame with `priority: "next"`.
      Proven by delivering into a real live session and watching it arrive, not only against
      a test socket. The phone says "Sent to <name>", or why it did not land.

## Next
- [ ] **Send-on-release vs confirm-before-send.** Today the transcript goes straight in on
      release. Speaking into a busy session is not undoable, so decide whether the phone should
      show the text for approval first — a toggle next to hold/tap is the obvious shape.
- [ ] A delivered message arrives labelled as coming from another Claude session, not from JJ.
      If the receiving session should treat it as its own user speaking, the frame needs
      whatever marks a message as the operator's — worth reading Claude Code's peer protocol
      before guessing.
- [ ] Guard against pid reuse before delivering. The key file carries `procStart`, which is how
      Claude Code itself avoids messaging a recycled pid; `deliver()` does not check it. Records
      are read fresh on every request today, so the window is small — it opens the moment
      anything caches them.
- [ ] Panes under launchd. `it2` cannot get iTerm's Python API approval from a background
      agent, so window/tab data and Focus on Mac are missing unless the daemon runs in a
      terminal. Candidate fix: let the menu bar app (a real GUI app, which can hold the
      permission) collect pane data and POST it to the daemon.
- [ ] Summary latency is ~30 s cold. Cache is per activity blob; consider summarising on the
      Mac's own schedule so the phone reads a ready answer.
- [ ] A column scrolls vertically now that a press has to settle before it records, but the
      two gestures still share a surface. Watch whether a slow, deliberate scroll ever starts
      a clip in real use.
