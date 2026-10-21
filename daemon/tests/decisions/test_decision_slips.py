"""`slip.py` writes a decision, `answer.py` reads one back — and checks the proof itself."""

import asyncio
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from decision_kit import AID, SID, answering, proof_for

from deckhand_daemon import config
from deckhand_daemon.decisions import pages
from deckhand_daemon.mcp import here, slips

SCRIPTS = Path(__file__).resolve().parents[3] / "skills" / "deckhand" / "scripts"


def run(script, *args):
    """As a session runs it, with the daemon's data dir handed down for the key check."""
    env = dict(os.environ) | {"CLAUDE_CODE_SESSION_ID": SID,
                              "DECKHAND_DATA_DIR": str(config.data_dir())}
    done = subprocess.run([sys.executable, str(SCRIPTS / script), *args],
                          capture_output=True, text=True, check=False, env=env)
    return done.returncode, done.stdout.strip(), done.stderr.strip()


def ask(project, *args):
    return run("slip.py", "--dir", str(project), "--title", "Ship it?", *args)


def test_a_confirm_declares_itself_a_decision(project):
    code, out, err = ask(project, "--kind", "confirm", "--option", "Ship", "--option", "Hold",
                         "--action", "push the tag, nothing else", "--expires-hours", "2")
    assert code == 0, err
    found = pages.declared(Path(out))
    assert found["decision"] == "confirm" and found["choices"] == ["Ship", "Hold"]
    assert found["action"] == "push the tag, nothing else"
    assert abs(found["expires"] - (time.time() + 7200)) < 60


def test_a_pick_and_a_text_are_decisions_too_and_aloud_is_not(project):
    _, picked, _ = ask(project, "--kind", "pick", "--option", "a", "--option", "b", "--key", "p")
    _, texted, _ = ask(project, "--kind", "text", "--option", "Name", "--key", "t")
    _, aloud, _ = ask(project, "--kind", "aloud", "--question", "q:Why?", "--key", "l")
    assert pages.declared(Path(picked)) | {"expires": 0} == {
        "decision": "pick", "choices": ["a", "b"], "action": "Ship it?", "expires": 0}
    assert pages.declared(Path(texted))["choices"] == ["Name"]
    assert pages.declared(Path(aloud)) is None


def test_a_confirm_without_an_action_is_refused(project):
    code, _, err = ask(project, "--kind", "confirm")
    assert code != 0 and "--action" in err
    assert not (project / ".deckhand").exists()


def test_re_asking_an_answered_decision_keeps_and_prints_the_answer(project, phone, key, typed):
    _, out, _ = ask(project, "--kind", "confirm", "--action", "ship", "--key", AID)
    page = Path(out)
    answering(phone[0], proof_for(key, page))
    before = page.read_bytes()

    code, again, err = ask(project, "--kind", "confirm", "--action", "ship more", "--key", AID)

    assert code == 0, err
    said = json.loads(again)
    assert said["id"] == AID and said["answered"] is True and said["verified"] is True
    assert page.read_bytes() == before
    assert page.with_name(f"{AID}.answer.json").exists()


def test_the_tool_hands_back_the_answer_instead_of_asking_twice(project, phone, key, typed,
                                                                monkeypatch):
    monkeypatch.setattr(here, "mine", lambda: {"sessionId": SID, "cwd": str(project)})
    made = asyncio.run(slips.ask_on_phone("Ship it?", action="ship", key=AID))
    assert made["waiting"] is True
    answering(phone[0], proof_for(key, Path(made["page"])))

    again = asyncio.run(slips.ask_on_phone("Ship it?", action="ship", key=AID))
    assert again["answered"] is True and again["verified"] is True and again["id"] == AID
    assert asyncio.run(slips.read_answer(AID))["verified"] is True
    assert "action" in asyncio.run(slips.ask_on_phone("Ship it?", key="other"))["error"]


def test_answer_py_checks_the_proof_rather_than_the_file(project, phone, key, typed):
    _, out, _ = ask(project, "--kind", "confirm", "--action", "ship", "--key", AID)
    answering(phone[0], proof_for(key, Path(out)))

    code, said, _ = run("answer.py", AID, "--dir", str(project))
    assert code == 0
    assert json.loads(said) == {"value": {"answer": True}, "verified": True,
                                "device": "JJ's iPhone", "fingerprint": phone[1]["fingerprint"]}

    # The same file, its value edited by hand: the signature no longer covers it.
    answer = Path(out).with_name(f"{AID}.answer.json")
    answer.write_text(json.dumps(json.loads(answer.read_text()) | {"value": {"answer": False}}))
    assert json.loads(run("answer.py", AID, "--dir", str(project))[1])["verified"] is False
