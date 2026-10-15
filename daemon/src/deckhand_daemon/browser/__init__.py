"""What a web page on another origin may ask this Mac: is it there, can it hear, and hear this.

Two routes, `GET /health` and `POST /transcribe`, and the CORS that lets a page call them. Built
for the Jaimes chat in wallgen's web UI, whose mic button sends a recorded clip and puts the words
in its composer; nothing is delivered anywhere.

- **CORS is an allow-list of two origins on two paths** (`routes.ORIGINS`, `routes.OPEN`). Every
  other route stays exactly as unreachable from a browser as before, preflight and all: a page
  that could call `/sessions/{id}/say` would be speaking into a session as the person.
- **`/transcribe` takes a token scoped to it** (`pairing.TRANSCRIBE`, minted by
  `python -m deckhand_daemon.pairing transcribe-token`), as well as every token `allows` takes. A page keeps that token in localStorage, where any script
  on the page can read it, so it must not be able to do more than turn audio into text.
- **The clip lives in a temp folder for the length of the request** and is gone afterwards,
  unlike a clip said to a session, which is kept beside the session it was said to.
- **Private Network Access.** A public page calling a LAN address gets a preflight carrying
  `Access-Control-Request-Private-Network`, and is answered with the matching allow header.
"""
