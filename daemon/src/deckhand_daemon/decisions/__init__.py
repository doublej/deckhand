"""Decisions: the slips whose answer carries the person's authority, and the proof that it does.

A `confirm`, `pick` or `text` slip written by `skills/deckhand/scripts/slip.py` declares itself a
decision in its own `<head>` — its kind, its choices, the one line of what a yes allows, and when
the question lapses (`pages.py`). Every other slip is a page like any other and is untouched by
anything in here.

**The token cannot say who tapped, so the phone's key does.** This Mac's token is a file every
agent on it can read, and the phone holds that same token, so nothing about a request carrying it
tells the person from a session that curled the route. A decision's answer is therefore signed on
the phone by a key that never leaves it (`proofs.py`), registered once with a token only a
paired-by-code device holds (`pairing/routes.py`). `answering.py` refuses anything that does not
verify, is bound to an older version of the page, has lapsed, or comes second.

**A verified answer goes back as the person, to the asker only** (`delivery.py`): the keyboard
route whatever the presence, addressed by the exact session id, never typed into a pane that is
showing a permission prompt, and retried by the push sweep until it lands or lapses.

**One notification per decision** (`announcing.py`): the sweep sends one alert with the decision
on it, the Live Activity moves silently, and which triples were announced is kept on disk so a
restart neither misses one nor repeats one.

`docs/artifacts.md` is the contract; `docs/agent-surface.md` says what this does and does not
fence.
"""
