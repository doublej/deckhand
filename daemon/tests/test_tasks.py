import pytest

from deckhand_daemon import tasks


@pytest.fixture(autouse=True)
def store(tmp_path, monkeypatch):
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path / "data"))


def test_a_list_survives_between_runs_and_keeps_its_ids():
    first = tasks.add("s1", "the files tab")
    second = tasks.add("s1", "rename sessions")
    assert (first["id"], second["id"]) == ("t1", "t2")
    # A second reading is the same list, which is the whole reason it is a file.
    assert [t["text"] for t in tasks.load("s1")] == ["the files tab", "rename sessions"]


def test_the_same_ask_twice_is_one_task():
    first = tasks.add("s1", "The files tab")
    again = tasks.add("s1", "the files tab!")
    assert again["id"] == first["id"]
    assert len(tasks.load("s1")) == 1


def test_an_ask_moves_along_and_stays_where_it_was():
    tasks.add("s1", "one")
    tasks.add("s1", "two")
    assert tasks.set_state("s1", "t1", "done")["state"] == "done"
    assert [(t["id"], t["state"]) for t in tasks.load("s1")] == [("t1", "done"), ("t2", "todo")]


def test_nothing_can_be_invented_or_aimed_at_another_session():
    tasks.add("s1", "one")
    assert tasks.set_state("s1", "t9", "done") is None
    assert tasks.drop("s1", "t9") is None
    with pytest.raises(ValueError):
        tasks.set_state("s1", "t1", "nearly")
    # One store per session: a tool bound to s1 cannot reach s2's list.
    assert tasks.load("s2") == []


def test_dropping_loses_the_entry_and_says_so(caplog):
    tasks.add("s1", "withdrawn")
    with caplog.at_level("WARNING"):
        assert tasks.drop("s1", "t1")["text"] == "withdrawn"
    assert tasks.load("s1") == []
    assert "dropped task t1" in caplog.text


def test_the_model_is_shown_the_ids_it_has_to_use():
    tasks.add("s1", "the files tab")
    tasks.set_state("s1", "t1", "doing")
    assert tasks.render("s1") == "  t1 [~] the files tab"
    assert tasks.render("s2") == "  (empty)"


def test_the_file_has_a_ceiling_but_the_phone_decides_what_to_show(monkeypatch):
    monkeypatch.setattr(tasks, "MAX_KEPT", 3)
    for n in range(4):
        tasks.add("s1", f"ask {n}")
    tasks.set_state("s1", "t1", "done")
    tasks.add("s1", "ask 4")
    texts = [t["text"] for t in tasks.load("s1")]
    # The finished one went first, and nothing unfinished was touched.
    assert len(texts) == 3
    assert "ask 0" not in texts
