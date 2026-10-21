"""The three scripts the `deckhand` skill hands a session, run the way a session runs them.

They live outside this package on purpose — a session executes them as plain `python3` from
whatever folder it is working in, with no install step — so they are exercised as subprocesses
rather than imported. What is being defended is not the substitution itself but its anchors:
`slip.py` edits the demo pages under `demos/`, another agent edits those, and a slip that
quietly kept the demo's own question is the failure nobody notices. `demos/check.py` is the same
gate the demos pass, applied to what came out.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPTS = REPO / "skills" / "deckhand" / "scripts"
SID = "aaaa1111-2222-3333-4444-555566667777"

# The demo gate, reached by path because `demos/` is a folder of pages rather than a package.
sys.path.insert(0, str(REPO / "demos"))
import check


def run(script, *args, session=""):
    """As a session runs it, with the id Claude Code injects into every Bash call spelled out.

    Spelled rather than inherited: this suite is itself run from inside a session, so a test
    leaving `CLAUDE_CODE_SESSION_ID` alone would file its slips under whoever ran it and prove
    nothing about either scope.
    """
    env = dict(os.environ) | {"CLAUDE_CODE_SESSION_ID": session}
    done = subprocess.run([sys.executable, str(SCRIPTS / script), *args],
                          capture_output=True, text=True, check=False, env=env)
    return done.returncode, done.stdout.strip(), done.stderr.strip()


def slip(tmp_path, *args, session=""):
    code, out, err = run("slip.py", "--dir", str(tmp_path), *args, session=session)
    assert code == 0, err
    page = Path(out)
    assert page == tmp_path / ".deckhand" / "artifacts" / session / page.name
    title, faults = check.check(page)
    assert faults == [], faults
    return page, page.read_text(), title


def test_a_decision_page_is_its_words_and_the_choices_are_the_apps(tmp_path):
    """The app draws a decision's controls under the page; a second copy on it was dead weight."""
    page, said, title = slip(tmp_path, "--kind", "pick", "--title", "Which branch",
                             "--note", "Three worktrees are waiting.",
                             "--option", "develop", "--option", "main")

    assert page.name == "which-branch.html"
    assert title == "Which branch"
    assert '<p class="lead">Three worktrees are waiting.</p>' in said
    assert "&quot;develop&quot;, &quot;main&quot;" in said  # the choices, in the meta tag only
    assert "<input" not in said and "<button" not in said and "<script>" not in said
    assert "feature/artifacts" not in said


def test_a_note_keeps_its_paragraphs_bullets_and_headings(tmp_path):
    _, said, _ = slip(tmp_path, "--kind", "confirm", "--title", "Ship it?", "--action", "ship",
                      "--note", "Gates are clean.\n\n## What ran\n- `just check`\n- **all** green"
                                "\nThen <this>.")

    assert '<p class="lead">Gates are clean.</p>' in said
    assert "<h2>What ran</h2>" in said
    assert "<ul><li><code>just check</code></li><li><strong>all</strong> green</li></ul>" in said
    assert "<p>Then &lt;this&gt;.</p>" in said


def test_an_aloud_slip_declares_its_questions_and_the_app_reads_that_block(tmp_path):
    _, said, _ = slip(tmp_path, "--kind", "aloud", "--title", "Before I start",
                      "--question", "scope:How far should this go?",
                      "--question", "deadline:Is there a date this has to be done by?")

    block = said.split('id="deckhand-aloud">')[1].split("</script>")[0]
    declared = json.loads(block)
    assert [q["id"] for q in declared["questions"]] == ["scope", "deadline"]
    assert declared["questions"][0]["ask"] == "How far should this go?"


def test_rewriting_a_slip_takes_the_old_answer_with_it(tmp_path):
    """Any slip but a decision: an aloud slip asked again is asked afresh."""
    asked = ("--kind", "aloud", "--title", "Name it", "--question", "name:What is it called?")
    page, _, _ = slip(tmp_path, *asked)
    beside = page.with_name("name-it.answer.json")
    beside.write_text(json.dumps({"id": "name-it", "answeredAt": 1.0, "value": {"answer": "a"}}))

    slip(tmp_path, *asked)

    assert not beside.exists()


def test_a_slug_that_could_be_a_path_is_refused(tmp_path):
    code, _, err = run("slip.py", "--dir", str(tmp_path), "--kind", "text",
                       "--title", "x", "--slug", "../escape")

    assert code != 0 and "not a slip id" in err


def test_a_slip_is_filed_under_the_session_that_wrote_it(tmp_path):
    """The default, and the whole point: only the session that asked lists it or is answered."""
    page, _, _ = slip(tmp_path, "--kind", "text", "--title", "Name it", session=SID)

    assert page.parent == tmp_path / ".deckhand" / "artifacts" / SID
    page.with_name("name-it.answer.json").write_text(json.dumps({"value": {"answer": "ok"}}))
    code, out, _ = run("answer.py", "--dir", str(tmp_path), "name-it", session=SID)

    assert code == 0 and json.loads(out)["value"] == {"answer": "ok"}


def test_a_session_reads_back_a_slip_belonging_to_the_folder(tmp_path):
    """A flat slip is the folder's, so a session working there answers the same page."""
    page, _, _ = slip(tmp_path, "--kind", "text", "--title", "Name it")
    page.with_name("name-it.answer.json").write_text(json.dumps({"value": {"answer": "ours"}}))

    code, out, _ = run("answer.py", "--dir", str(tmp_path), "name-it", session=SID)

    assert code == 0 and json.loads(out)["value"] == {"answer": "ours"}


def test_a_session_id_that_could_be_a_path_is_refused(tmp_path):
    """It becomes a folder name here and a path segment in the daemon. Same rule, both ends."""
    code, _, err = run("slip.py", "--dir", str(tmp_path), "--kind", "text",
                       "--title", "x", session="../escape")

    assert code != 0 and "not a session id" in err
    assert not (tmp_path / ".deckhand").exists()


def test_the_answer_is_printed_once_it_lands_and_a_false_one_counts(tmp_path):
    page, _, _ = slip(tmp_path, "--kind", "confirm", "--title", "Ship it", "--action", "ship")
    code, _, _ = run("answer.py", "--dir", str(tmp_path), "ship-it")
    assert code == 1

    page.with_name("ship-it.answer.json").write_text(
        json.dumps({"id": "ship-it", "answeredAt": 1.0, "value": {"answer": False}}))
    code, out, _ = run("answer.py", "--dir", str(tmp_path), "ship-it")

    assert code == 0 and json.loads(out) == {"value": {"answer": False}, "verified": False,
                                            "device": None, "fingerprint": None}


def test_half_a_written_answer_is_not_an_answer(tmp_path):
    page, _, _ = slip(tmp_path, "--kind", "confirm", "--title", "Ship it", "--action", "ship")
    page.with_name("ship-it.answer.json").write_text('{"id": "ship-it", "value": {"an')

    code, _, err = run("answer.py", "--dir", str(tmp_path), "ship-it")

    assert code == 1 and "has not been answered yet" in err


def logbook(tmp_path, *args, session=""):
    """As a session runs it: the verb first and the flags after it, which argparse insists on.

    Comes back with the page and the block it renders itself from, because that block is the
    whole of what `logbook.py` writes — anything wrong with it is wrong on the phone.
    """
    code, out, err = run("logbook.py", *args, "--dir", str(tmp_path), session=session)
    assert code == 0, err
    page = Path(out)
    title, faults = check.check(page)
    assert faults == [], faults
    block = page.read_text().split('id="deckhand-logbook">')[1].split("</script>")[0]
    return page, json.loads(block), title


def test_a_logbook_belongs_to_the_folder_and_keeps_its_state_beside_the_page(tmp_path):
    """Flat, and its state next to it — the two halves of "another session can pick this up"."""
    page, block, title = logbook(tmp_path, "start", "Moving the reader", "--standing", "Porting.")

    assert page == tmp_path / ".deckhand" / "artifacts" / "logbook.html"
    assert page.with_name("logbook.log.json").is_file()
    assert title == "Moving the reader"
    assert "<p class=\"lead\">Porting.</p>" in page.read_text()
    assert block == {"finished": False, "updated": block["updated"], "earlier": 0,
                     "counts": {"done": 0, "doing": 0, "blocked": 0, "note": 0}, "entries": []}


def test_a_second_session_appends_to_the_one_the_first_started(tmp_path):
    """The difference from a slip, and the reason a logbook is flat: a job outlives a session."""
    started, _, _ = logbook(tmp_path, "start", "Moving the reader", session=SID)
    page, block, _ = logbook(tmp_path, "add", "done", "Read every caller", "Nine of them",
                             session="9999aaaa-bbbb-cccc-dddd-eeeeffff0000")

    assert page == started
    assert [(e["state"], e["step"], e["said"]) for e in block["entries"]] == [
        ("done", "Read every caller", "Nine of them")]
    assert block["counts"]["done"] == 1


def test_rewriting_a_logbook_leaves_the_answer_where_it_is(tmp_path):
    """The opposite of the rule for a question, and deliberately so.

    Rewriting a question is asking it again, so `slip.py` takes its old answer with it. Rewriting
    a logbook is the same page saying more, and the note the person left on it an hour ago is
    still theirs — it survives every entry appended after it.
    """
    page, _, _ = logbook(tmp_path, "start", "Moving the reader")
    beside = page.with_name("logbook.answer.json")
    beside.write_text(json.dumps({"value": {"answer": "do the cutover tomorrow"}}))

    logbook(tmp_path, "add", "doing", "Writing the cutover")

    assert json.loads(beside.read_text())["value"] == {"answer": "do the cutover tomorrow"}


def test_the_page_draws_the_last_dozen_and_counts_the_rest(tmp_path):
    """A phone is a phone. The state file keeps everything; the page says what it is not showing."""
    logbook(tmp_path, "start", "Long one")
    for step in range(15):
        page, block, _ = logbook(tmp_path, "add", "done", f"Step {step}")

    assert len(block["entries"]) == 12
    assert block["entries"][0]["step"] == "Step 3"
    assert block["earlier"] == 3
    # Over everything, not over what is drawn: "12 done" under a job with fifteen is worse than
    # no tally at all.
    assert block["counts"]["done"] == 15
    assert len(json.loads(page.with_name("logbook.log.json").read_text())["entries"]) == 15


def test_finishing_says_so_and_leaves_a_last_standing_line(tmp_path):
    logbook(tmp_path, "start", "Moving the reader")
    page, block, _ = logbook(tmp_path, "finish", "Cut over, no session lost its place.")

    assert block["finished"] is True
    assert "Cut over, no session lost its place." in page.read_text()


def test_appending_to_a_logbook_nobody_started_says_how_to_start_one(tmp_path):
    code, _, err = run("logbook.py", "add", "done", "Step", "--dir", str(tmp_path))

    assert code != 0 and "start one with" in err


def test_a_second_job_cannot_stand_on_an_unfinished_logbook(tmp_path):
    """`logbook` is the default slug, so this is what stops one job wiping another's history."""
    logbook(tmp_path, "start", "Moving the reader")
    code, _, err = run("logbook.py", "start", "Something else", "--dir", str(tmp_path))
    assert code != 0 and "already going" in err

    logbook(tmp_path, "finish")
    _, block, title = logbook(tmp_path, "start", "Something else")

    assert title == "Something else" and block["entries"] == []


def test_a_paragraph_is_refused_rather_than_quietly_cut(tmp_path):
    logbook(tmp_path, "start", "Moving the reader")
    code, _, err = run("logbook.py", "add", "note", "Step", "word " * 100, "--dir", str(tmp_path))

    assert code != 0 and "the cap is 300" in err
