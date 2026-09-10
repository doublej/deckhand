# Prompt review and improvement plan

Reviewed 2026-09-10 against the current call sites, tests, and the model-specific
`prompt-crafter` guidance. The targets are Claude Opus 5 for prompt crafting, Claude Haiku 4.5
for briefings, and an inherited or unknown Claude Code model for project instructions and
session messages.

## Scope

This review covers every static instruction or generated message found that a model can read:

- `daemon/src/deckhand_daemon/prompts/briefing.md`, including its task-tool descriptions
- `daemon/src/deckhand_daemon/prompts/crafting.md`
- `daemon/src/deckhand_daemon/prompts/idle-check.md`
- the attribution, image attachment, and slip-answer messages in `deliver.py` and `artifacts.py`
- `CLAUDE.md`, `agent.md`, and `.claude/agents/verify-runner.md`
- the SessionStart messages emitted by `check_template_update.py` and
  `check_library_freshness.py`

Human-facing app copy, transcription hints, user-authored messages, ticket contents, and code
comments are outside the prompt inventory.

## Findings

| Priority | Surface | Verdict | Evidence and effect |
|---|---|---|---|
| P0 | SessionStart hooks | Fail | The template hook orders the agent to stop all work until the user decides; the library hook assigns a network-heavy audit on every startup and resume. Both can replace the user's actual task. Claude Code's hook guidance recommends factual dynamic context, while static instructions belong in `CLAUDE.md`. |
| P0 | `crafting.md` | Fail | Lines 23–27 say `<model_profiles>` contains the target calibration and forbid other references. The installed skill says that section deliberately omits the clauses and requires `references/lint-<target>.md` on every path. The filter can skip the guidance it exists to apply. |
| P0 | `idle-check.md` | Fail | It arrives through a peer channel that explicitly carries no user authority, yet tells the session to continue work. The inline task text is not marked as data, and “two or three lines” can conflict with naming every open id. |
| P1 | `CLAUDE.md` | Fail | It is 527 lines and about 7,000 words. Most of its 347-line “Quirks” section is feature history or path-specific context, so every session pays for facts it rarely needs. Claude Code recommends keeping each `CLAUDE.md` under 200 lines and using path-scoped rules. |
| P1 | `agent.md` + `verify-runner.md` | Fail | `agent.md` still says iOS 26 while `Package.swift` and `project.yml` use iOS 18, omits daemon and demo checks from its command summary, and shows a generic project tree. The verifier is told to run beside active edits and may auto-fix the same shared worktree, making its result race with the caller. |
| P1 | Briefing input boundary | Warn | `asks` and `activity` are raw transcript text interpolated inside XML-looking tags. The system prompt labels them as evidence, but embedded closing tags can escape that visual boundary. Current tests check assembly, not adversarial content. |
| P1 | Prompt tests and loader | Warn | The shipped prompt list is hand-maintained. Placeholder tests infer a hole from any `{`, although `Prompt.filled` intentionally allows literal JSON braces. Tests stub model output, so they prove transport and failure handling but not prompt behavior. |
| P2 | `briefing.md` | Warn | The task, evidence rules, tool boundaries, status priority, and output shape are strong. The finish clause permits tool preambles while also requiring the briefing alone; simplify that final contract and test the five status branches. |
| P2 | Generated session messages | Warn | The slip-answer message is concrete and recoverable through its file path. Attribution is explicit. An image with no accompanying text produces only “attached image: path,” leaving the requested action undefined; decide in the UI or message contract whether image-only sends are valid. |
| Keep | Model configuration | Pass | `claude-opus-5` with medium effort is supported, and `claude-haiku-4-5-20251001` is a valid pinned model id. Change models only after the same behavior corpus is compared for quality, latency, and cost. |

The current 29 focused Python tests pass. They do not contradict these findings because none
executes a real model or checks the hook instructions, authority boundary, or skill-reference
selection.

## Improvement plan

### 1. Remove unsolicited work from startup

Change both SessionStart hooks before tuning model prose.

- Make the template hook emit a short fact: local version, available version, preview command,
  and “do not apply automatically.” Do not block unrelated work.
- Remove dependency auditing from SessionStart. Expose it as an explicit command or scheduled
  task; keep startup output to a due/not-due fact if a reminder is still wanted.
- Return structured hook JSON when the distinction between user-visible warning and model
  context matters. Add unit tests for up-to-date, update-available, snoozed, and failure paths.

Done when a fresh or resumed session can immediately perform the user's request without being
assigned scaffold or dependency work.

### 2. Repair the two action prompts

- In `crafting.md`, align the read contract with the current skill: read `SKILL.md`, resolve the
  target, then read exactly the routed lint reference it names. Keep the local rewrite-only
  output contract as the higher-priority task contract.
- In `idle-check.md`, label the session name and open asks as data. Ask for one compact status per
  id. Permit continuation only when the session's own user conversation already authorizes it;
  the daemon message itself grants no authority. Keep the misroute guard.
- Give the idle response a parseable shape so future reconciliation does not depend on free prose.

Done when crafting preserves request type, negation, literals, and uncertainty across the test
corpus, and every idle reply accounts for every id without treating the nudge as user authority.

### 3. Rebuild the project instruction hierarchy

- Reduce root `CLAUDE.md` below 200 lines: product purpose, architecture map, exact verification
  commands, cross-cutting invariants, and the few rules that must survive compaction.
- Move daemon-only, SwiftUI-only, artifact-only, delivery-only, and prompt-only rules into
  `.claude/rules/*.md` with `paths:` frontmatter. Move incident history and measurements into
  ordinary docs, linked from the relevant rule when useful.
- Rewrite `agent.md` as the verifier's small, authoritative command contract or remove the extra
  layer and point the verifier at one source. Correct the iOS target and full `just check` contents.
- Run verification on a stable snapshot. Prefer `isolation: worktree` for `verify-runner`; if it
  must share the checkout, forbid auto-fixes while the caller is editing and report a stale result.

Done when no fact is duplicated with different values, root instructions stay below 200 lines,
and opening a daemon or Swift file loads only the relevant scoped rules.

### 4. Make prompt assembly explicit

- Discover shipped prompt Markdown files rather than maintaining `SHIPPED` by hand.
- Declare required variables per prompt and have `filled` reject missing or unknown values. Stop
  using “any brace means a hole,” so literal JSON remains legal.
- Serialize briefing evidence as data, preferably a JSON object, instead of interpolating raw
  transcript text into escapable tags.
- Keep each model, effort/thinking setting, timeout, tool list, and user-turn task in the same
  prompt specification, with schema validation for required fields and types.

Done when malformed metadata, missing variables, extra variables, and boundary-breaking evidence
all fail deterministically before a live model call.

### 5. Add behavior evaluations, then tune

Use the existing pytest stack; add no evaluation framework.

- Deterministic tests: prompt discovery, metadata schemas, variable contracts, hook outputs, data
  serialization, and exact transport authority.
- Opt-in live cases for crafting: already-clear input, question versus implementation, multiple
  requests, negation, self-correction, literals, and prompt-injection-shaped source text.
- Opt-in live cases for briefing: waiting, blocked, done, working, unclear, duplicate asks,
  withdrawn asks, partial completion, and adversarial transcript content.
- Score invariants and required fields rather than exact wording. Record model id, prompt revision,
  latency, token use, tool calls, and pass/fail so model or prompt changes can be compared.
- After the corpus passes, simplify `briefing.md`, decide image-only behavior, and benchmark Opus 5
  against a cheaper target for crafting. Keep the current models unless the measured result wins.

Done when deterministic checks run in `just check`, live evaluations have an explicit opt-in
command, and each production prompt has a small regression corpus tied to its actual failure modes.

## Rollout order

1. Hook messages and their tests.
2. Crafting and idle-check contracts plus behavior cases.
3. `CLAUDE.md`/rules split and verifier isolation.
4. Prompt loader contracts and briefing serialization.
5. Live evaluation baseline, prompt simplification, then model comparison.

The highest rollout risk is losing a critical invariant while splitting `CLAUDE.md`; keep
cross-cutting safety and verification rules in the root file because path-scoped rules reload
only when matching files are read. Live model evaluations are nondeterministic and billable, so
keep them explicit and rubric-based rather than part of the default quality gate.

## References

- [Claude Code project memory and path-scoped rules](https://code.claude.com/docs/en/memory)
- [Claude Code hook output and SessionStart behavior](https://code.claude.com/docs/en/hooks)
- [Claude Code subagent isolation and tool configuration](https://code.claude.com/docs/en/sub-agents)
- [Claude model ids and versioning](https://platform.claude.com/docs/en/about-claude/models/model-ids-and-versions)
- [Claude effort configuration](https://platform.claude.com/docs/en/build-with-claude/effort)
