# The filter chain

## What this is

What happens to a prompt between the phone and `deliver`. `run(Prompt) -> Outcome`.

```
kinds.py     # Prompt, Verdict, Outcome, Field, Filter — the contract, and only that
registry.py  # a filter declares itself here; known() describes them for the phone
config.py    # the saved chain, where list order is run order
runner.py    # runs it, and survives a filter that does not
routes.py    # GET and PUT /filters, knowing nothing about tokens
words.py     # the first filter: swap words dictation keeps getting wrong
crafting.py  # the prompt-crafting filter, whose agent is prompts/crafting.md
```

## Invariants

- **The chain is an ordered list, not a table.** Each step is
  `{"filter": name, "on": bool, "settings": {}}` in `filters.json` and **the array order is the
  run order**. Nothing is keyed by name, because the same filter may appear twice with different
  settings — a step is a position in a list, not an entry in a table. A step missing `on` is on.
- **A filter that raises is logged, noted as skipped, and the words carry on unchanged.** Only an
  explicit `Verdict.stop` ends the chain.
- **`PUT /filters` refuses a name this Mac does not have** rather than saving a step the runner
  would step over, because a step that silently does nothing looks exactly like one that silently
  fails.
- **A stop is not a delivery failure.** The daemon can answer `delivered: true` alongside a stop,
  so the app asks `Delivery.went` — `delivered && stoppedBy == nil` — and never `delivered` alone.
  The status line names the filter by its *title*, not its wire name.
- **Nothing on the filters wire is snake case by accident.** A setting like `max_words` must
  survive the round trip: the Swift client decodes `/filters` through a decoder with **no** key
  strategy, because `convertFromSnakeCase` rewrites dictionary keys too, not only struct keys.
  See `Sources/DeckhandKit/CLAUDE.md`.

## Adding a filter

1. Write it in this folder against `kinds.Filter`.
2. Declare it in `registry.py` with the title and fields the phone will draw.
3. If it needs a model, its prompt is a file in `../prompts/`, never a Python string.
4. Test it in `daemon/tests/filters/`.

## Verification

`daemon/tests/filters/` — pytest, inside `just daemon-test`.
