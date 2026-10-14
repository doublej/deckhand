"""A session's project and colour come out as JJ's statusline draws them."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

import pytest

from deckhand_daemon.sessions import project

STATUSLINE = Path.home() / ".claude" / "statusline" / "statusline.sh"


@pytest.mark.parametrize("text", ["", "a", "dev/multi-stack/deckhand", "ünïcode/dir", "x" * 300])
def test_cksum_is_posix_cksum(text):
    expected = subprocess.run(["cksum"], input=text.encode(), capture_output=True, check=True)
    assert project.cksum(text) == int(expected.stdout.split()[0])


@pytest.mark.skipif(not STATUSLINE.exists(), reason="no statusline on this machine")
def test_the_palettes_are_the_statuslines_own():
    script = STATUSLINE.read_text()
    for name, ours in (("dir_palette", project.DIR_PALETTE), ("par_palette", project.PAR_PALETTE)):
        found = re.search(rf"^{name}=\(([\d ]+)\)", script, re.MULTILINE)
        assert found and tuple(int(n) for n in found.group(1).split()) == ours


def test_the_key_is_dev_relative_under_the_dev_tree_and_bare_elsewhere():
    home = Path.home()
    assert project.key(str(home / "dev/multi-stack/deckhand")) == "dev/multi-stack/deckhand"
    assert project.key(str(home / "Documents/development/web/x")) == "dev/web/x"
    assert project.key("/tmp/elsewhere/thing") == "thing"


def test_xterm_colours():
    assert (project.xterm(1), project.xterm(39), project.xterm(244)) == (
        "#800000",
        "#00afff",
        "#808080",
    )


def test_a_subfolder_is_its_repos_project(tmp_path):
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    (tmp_path / "sub").mkdir()
    project._root.cache_clear()
    assert project.of(str(tmp_path / "sub"))["key"] == project.of(str(tmp_path))["key"]
    assert project.of(str(tmp_path))["color"].startswith("#")
