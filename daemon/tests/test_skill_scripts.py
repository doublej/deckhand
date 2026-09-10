"""The two scripts the `deckhand` skill hands a session, run the way a session runs them.

They live outside this package on purpose — a session executes them as plain `python3` from
whatever folder it is working in, with no install step — so they are exercised as subprocesses
rather than imported. What is being defended is not the substitution itself but its anchors:
`slip.py` edits the demo pages under `demos/`, another agent edits those, and a slip that
quietly kept the demo's own question is the failure nobody notices. `demos/check.py` is the same
gate the demos pass, applied to what came out.
"""

import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPTS = REPO / "skills" / "deckhand" / "scripts"

# The demo gate, reached by path because `demos/` is a folder of pages rather than a package.
sys.path.insert(0, str(REPO / "demos"))
import check


def run(script, *args):
    done = subprocess.run([sys.executable, str(SCRIPTS / script), *args],
                          capture_output=True, text=True, check=False)
    return done.returncode, done.stdout.strip(), done.stderr.strip()


def slip(tmp_path, *args):
    code, out, err = run("slip.py", "--dir", str(tmp_path), *args)
    assert code == 0, err
    page = Path(out)
    assert page == tmp_path / ".deckhand" / "artifacts" / page.name
    title, faults = check.check(page)
    assert faults == [], faults
    return page, page.read_text(), title


def test_a_pick_carries_its_options_and_nothing_of_the_demo(tmp_path):
    page, said, title = slip(tmp_path, "--kind", "pick", "--title", "Which branch",
                             "--note", "Three worktrees are waiting.",
                             "--option", "develop", "--option", "main")

    assert page.name == "which-branch.html"
    assert title == "Which branch"
    assert 'value="develop"' in said and 'value="main"' in said
    assert "feature/artifacts" not in said
    # The row that takes a typed answer stays: the page's own script selects on it.
    assert 'name="branch" value=""' in said


def test_a_confirm_says_back_the_words_on_its_own_buttons(tmp_path):
    _, said, _ = slip(tmp_path, "--kind", "confirm", "--title", "Tag 0.4.0 and push it?",
                      "--option", "Tag and push", "--option", "Hold")

    assert '<button id="yes" class="primary">Tag and push</button>' in said
    assert '<button id="no">Hold</button>' in said
    assert '(before.answer ? "Tag and push" : "Hold")' in said


def test_a_text_slip_starts_empty(tmp_path):
    _, said, _ = slip(tmp_path, "--kind", "text", "--title", "What should this be called?")

    assert '<input id="name" type="text" value=""' in said
    assert "artifacts" not in said


def test_an_aloud_slip_declares_its_questions_and_the_app_reads_that_block(tmp_path):
    _, said, _ = slip(tmp_path, "--kind", "aloud", "--title", "Before I start",
                      "--question", "scope:How far should this go?",
                      "--question", "deadline:Is there a date this has to be done by?")

    block = said.split('id="deckhand-aloud">')[1].split("</script>")[0]
    declared = json.loads(block)
    assert [q["id"] for q in declared["questions"]] == ["scope", "deadline"]
    assert declared["questions"][0]["ask"] == "How far should this go?"


def test_rewriting_a_slip_takes_the_old_answer_with_it(tmp_path):
    page, _, _ = slip(tmp_path, "--kind", "text", "--title", "Name it")
    beside = page.with_name("name-it.answer.json")
    beside.write_text(json.dumps({"id": "name-it", "answeredAt": 1.0, "value": {"answer": "a"}}))

    slip(tmp_path, "--kind", "text", "--title", "Name it")

    assert not beside.exists()


def test_a_slug_that_could_be_a_path_is_refused(tmp_path):
    code, _, err = run("slip.py", "--dir", str(tmp_path), "--kind", "text",
                       "--title", "x", "--slug", "../escape")

    assert code != 0 and "not a slip id" in err


def test_the_answer_is_printed_once_it_lands_and_a_false_one_counts(tmp_path):
    page, _, _ = slip(tmp_path, "--kind", "confirm", "--title", "Ship it")
    code, _, _ = run("answer.py", "--dir", str(tmp_path), "ship-it")
    assert code == 1

    page.with_name("ship-it.answer.json").write_text(
        json.dumps({"id": "ship-it", "answeredAt": 1.0, "value": {"answer": False}}))
    code, out, _ = run("answer.py", "--dir", str(tmp_path), "ship-it")

    assert code == 0 and json.loads(out) == {"answer": False}


def test_half_a_written_answer_is_not_an_answer(tmp_path):
    page, _, _ = slip(tmp_path, "--kind", "confirm", "--title", "Ship it")
    page.with_name("ship-it.answer.json").write_text('{"id": "ship-it", "value": {"an')

    code, _, err = run("answer.py", "--dir", str(tmp_path), "ship-it")

    assert code == 1 and "has not been answered yet" in err
