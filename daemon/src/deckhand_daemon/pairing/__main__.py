"""The person's side of pairing, at this Mac's terminal: `just pair`, `just devices`, `just forget`.

Not a `deckhand` command, on purpose: that command is the agent surface, and pairing hands a
device everything this Mac's token can do — it is the person's own, opened by someone standing
here (`mcp/refused.py`). This talks to the running daemon, because the window lives in its memory.
"""

from __future__ import annotations

import subprocess
import sys
import time
from urllib.parse import quote

import httpx

from .. import config
from . import window

BASE = f"http://127.0.0.1:{config.PORT}"


def _call(method: str, path: str) -> httpx.Response:
    try:
        answered = httpx.request(method, BASE + path, headers={config.TOKEN_HEADER: config.token()},
                                 timeout=10)
    except httpx.HTTPError:
        sys.exit(f"The Deckhand daemon is not answering on port {config.PORT}. `just daemon`, or "
                 "`just install-agent`, starts it.")
    if answered.status_code >= 400:
        sys.exit(f"The daemon said no ({answered.status_code}): {answered.text}")
    return answered


def pair() -> None:
    """Show a code, then wait for the device that types it — so the person sees it worked here."""
    before = {d["id"] for d in _call("GET", "/devices").json()["devices"]}
    opened = _call("POST", "/pair/open").json()
    print(f"\n    {window.spaced(opened['code'])}\n")
    print(f"Type this code on your phone or headset. It works once, for "
          f"{opened['seconds'] // 60} minutes.")
    while time.time() < opened["expires"]:
        time.sleep(1)
        new = [d for d in _call("GET", "/devices").json()["devices"] if d["id"] not in before]
        if new:
            print(f"Paired: {new[0]['name']} ({new[0]['kind']}), id {new[0]['id']}.")
            return
    print("The code ran out. `just pair` opens a new one.")


def devices() -> None:
    found = _call("GET", "/devices").json()["devices"]
    if not found:
        print("No device has paired with a code yet. This Mac's own token (`just token`) still "
              "works wherever it was typed.")
    for d in found:
        seen = time.strftime("%Y-%m-%d %H:%M", time.localtime(d["seen"]))
        print(f"{d['id']}  {d['name']} ({d['kind']}), last seen {seen}")


def forget(device_id: str) -> None:
    _call("DELETE", f"/devices/{device_id}")
    print(f"{device_id} can no longer reach this Mac.")


def transcribe_token(name: str) -> None:
    """Straight onto the clipboard: the token is never printed, so it is in no scrollback."""
    minted = _call("POST", f"/pair/transcribe?name={quote(name)}").json()
    subprocess.run(["pbcopy"], input=minted["token"].encode(), check=True)
    print(f"A transcribe-only token for {minted['device']['name']} (id {minted['device']['id']}) "
          "is on the clipboard. It can call POST /transcribe and nothing else; "
          f"`just forget {minted['device']['id']}` takes it back.")


def manager_token(name: str) -> None:
    """The same, for `/mcp`: the manager's tools and nothing else."""
    minted = _call("POST", f"/pair/manager?name={quote(name)}").json()
    subprocess.run(["pbcopy"], input=minted["token"].encode(), check=True)
    print(f"A manager-only token for {minted['device']['name']} (id {minted['device']['id']}) "
          "is on the clipboard. Send it as `Authorization: Bearer <token>` to /mcp; "
          f"`just forget {minted['device']['id']}` takes it back.")


def main(argv: list[str]) -> None:
    match argv:
        case ["pair"]:
            pair()
        case ["devices"]:
            devices()
        case ["forget", device_id]:
            forget(device_id)
        case ["transcribe-token", name]:
            transcribe_token(name)
        case ["manager-token", name]:
            manager_token(name)
        case _:
            sys.exit("usage: python -m deckhand_daemon.pairing pair | devices | forget ID | "
                     "transcribe-token NAME | manager-token NAME")


if __name__ == "__main__":
    main(sys.argv[1:])
