"""A model chosen for one start reaches the launch, and a model nobody offers never does."""

from __future__ import annotations

import asyncio

from deckhand_daemon.manager import opening


def _start(monkeypatch, tmp_path, model):
    asked = []
    monkeypatch.setattr(opening.registry, "here", lambda: "m2")
    monkeypatch.setattr(opening.registry, "machines",
                        lambda: [type("M", (), {"id": "m2"})()])
    monkeypatch.setattr(opening.starting, "start",
                        lambda cwd, **kw: (asked.append(kw["model"]), (None, "stop here"))[1])
    answer = asyncio.run(opening.begin(str(tmp_path), "", model))["content"][0]["text"]
    return asked, answer


def test_the_model_said_for_one_start_goes_to_that_start(monkeypatch, tmp_path):
    assert _start(monkeypatch, tmp_path, " Sonnet ")[0] == ["sonnet"]


def test_empty_leaves_the_folder_its_own_model(monkeypatch, tmp_path):
    assert _start(monkeypatch, tmp_path, "")[0] == [""]


def test_a_model_this_mac_does_not_offer_starts_nothing(monkeypatch, tmp_path):
    asked, answer = _start(monkeypatch, tmp_path, "gpt-6")
    assert asked == [] and "sonnet" in answer
