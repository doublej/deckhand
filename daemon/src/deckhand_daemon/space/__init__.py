"""The space: everything open in the person's headset beside the sessions, and where it all is.

The headset (`~/dev/multi-stack/deckhand-xr`) draws every live session as a **plane**. Sessions
come from the listing and are never kept here. What is kept is the rest — a web page or a Mac
window opened beside a session — and the **pose** of every plane, sessions included, so a plane
stays where the person put it across a restart of either end. Kept by the daemon rather than the
headset so that an agent inside a session can add to it: `open_plane` is the reason this exists.

`stored.py` is the one document, `space.json`. `routes.py` is the wire for it, and `windows.py`
the pass-through to `deckhand-windows`, the helper that lists this Mac's windows and streams one.
`screen.py` reads a session's pane for its terminal plane — with iTerm's own cell styles through
`iterm.py` and `styled.py` once that API is approved — and `theme.py` says what iTerm draws it
with. `docs/space.md` is the long version.

The same import shape as `bindings/`: `routes` is never imported here, because `app.py` is the
only thing that decides when FastAPI and the rest of the daemon get pulled in.
"""
