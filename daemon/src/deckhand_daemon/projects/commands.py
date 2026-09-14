"""The `just` recipes a project offers, and running one — a deploy, a server, anything else.

Listing shells out to `just --dump --dump-format json` rather than parsing the file: just already
knows its own private recipes, groups and parameters, and a hand-rolled parser would only be a
worse copy of that. Running one is fire-and-forget — the phone polls `status` rather than holding
a connection open for however long a deploy takes — and `_running` is this process's memory of
what it started, keyed by the folder and the recipe together so a dev server and a deploy in the
same project do not fight over one slot. It does not survive a daemon restart, which matches the
same limitation atlas's own `/api/run` accepts for the same reason: this is a convenience for the
phone, not a process supervisor.
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import time
from dataclasses import dataclass
from hashlib import sha1
from pathlib import Path

from ..config import data_dir
from ..log import log

DUMP_TIMEOUT = 5.0
# Bounded so a poll every few seconds never ships a deploy's entire scrollback over the LAN.
LOG_TAIL_BYTES = 8_000


@dataclass(slots=True)
class _Running:
    popen: subprocess.Popen
    started_at: float
    log_path: Path


_running: dict[tuple[str, str], _Running] = {}


def list_recipes(path: str) -> dict:
    """Every runnable recipe in that folder, or none if it has no justfile."""
    try:
        result = subprocess.run(
            ["just", "--dump", "--dump-format", "json"],
            cwd=path, capture_output=True, text=True, timeout=DUMP_TIMEOUT, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        log.info("just --dump failed for %s: %s", path, error)
        return {"has_justfile": False, "recipes": []}
    if result.returncode != 0:
        return {"has_justfile": False, "recipes": []}
    try:
        dump = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        log.warning("just --dump gave unreadable json for %s: %s", path, error)
        return {"has_justfile": False, "recipes": []}
    recipes = [
        _recipe(recipe) for recipe in dump.get("recipes", {}).values() if not recipe.get("private")
    ]
    return {"has_justfile": True, "recipes": recipes}


def _recipe(recipe: dict) -> dict:
    return {
        "name": str(recipe.get("name") or ""),
        "doc": str(recipe.get("doc") or ""),
        "group": _group(recipe.get("attributes") or []),
        "needs_args": _needs_args(recipe.get("parameters") or []),
    }


def _group(attributes: list[dict]) -> str:
    return next((str(a["group"]) for a in attributes if "group" in a), "")


def _needs_args(parameters: list[dict]) -> bool:
    """`*args` takes zero or more and is never required; a bare or `+args` parameter with no
    default has to be given one, and there is nowhere on the phone yet to type it."""
    return any(p.get("default") is None and p.get("kind") != "star" for p in parameters)


def run(path: str, recipe: str) -> dict:
    """Start `just <recipe>` in that folder, detached, its output going to a log this process
    remembers the path of. Replaces whatever was already running under the same recipe."""
    key = (path, recipe)
    existing = _running.get(key)
    if existing and existing.popen.poll() is None:
        _kill(existing)
    log_path = _log_path(path, recipe)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        popen = subprocess.Popen(
            ["just", recipe], cwd=path, stdout=fd, stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    finally:
        os.close(fd)  # the child holds its own copy
    started = _Running(popen=popen, started_at=time.time(), log_path=log_path)
    _running[key] = started
    return {"pid": popen.pid, "started_at": started.started_at}


def stop(path: str, recipe: str) -> bool:
    """Kill whatever is running under that recipe. False when there was nothing to kill."""
    existing = _running.get((path, recipe))
    if not existing or existing.popen.poll() is not None:
        return False
    _kill(existing)
    return True


def status(path: str, recipe: str) -> dict:
    """Whether it is still running, and the tail of what it has said so far."""
    existing = _running.get((path, recipe))
    if existing is None:
        return {"running": False, "pid": 0, "started_at": 0.0, "exit_code": None,
                 "log": _tail(_log_path(path, recipe))}
    exit_code = existing.popen.poll()
    return {
        "running": exit_code is None,
        "pid": existing.popen.pid,
        "started_at": existing.started_at,
        "exit_code": exit_code,
        "log": _tail(existing.log_path),
    }


def _kill(existing: _Running) -> None:
    """Whole process group: `just` forks whatever the recipe runs, and a plain kill of `just`
    itself would leave that child holding on — the same reason atlas's `/api/run` kills `-pid`."""
    try:
        os.killpg(existing.popen.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass


def _log_path(path: str, recipe: str) -> Path:
    key = sha1(f"{path}::{recipe}".encode()).hexdigest()[:16]
    return data_dir() / "commands" / f"{key}.log"


def _tail(path: Path) -> str:
    try:
        with path.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            handle.seek(max(0, size - LOG_TAIL_BYTES))
            return handle.read().decode("utf-8", errors="replace")
    except FileNotFoundError:
        return ""
