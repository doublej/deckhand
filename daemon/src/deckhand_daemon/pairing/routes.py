"""The pairing routes: one open to the LAN, the rest for this Mac alone.

`POST /pair` is the only route besides `/health` that answers without a token, and it does
nothing at all unless the person at the Mac has opened a window (`window.py`). Everything that
opens a window or lists or revokes devices needs **this Mac's own token** — a paired phone holds
a device token and gets a 403 here, so no device can open a window for another or revoke a
sibling.

`/devices/key` is the other way round: only a **device** token, never this Mac's, may file a
signing key, because a key filed with a token every agent can read proves nothing.
"""

from __future__ import annotations

import base64
import secrets
from typing import Annotated

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request
from pydantic import BaseModel, Field

from .. import beacon, config, plugin
from ..decisions import proofs
from ..log import log
from . import MANAGER, TRANSCRIBE, allows, devices, window

router = APIRouter()


def require_mac(x_deckhand_token: str = Header(default="")) -> None:
    """This Mac's own token, the file `just token` prints — never a device's."""
    if not x_deckhand_token or not allows(x_deckhand_token):
        raise HTTPException(status_code=401, detail="bad token")
    if not secrets.compare_digest(x_deckhand_token, config.token()):
        raise HTTPException(status_code=403, detail="only this Mac pairs and unpairs devices")


class Asking(BaseModel):
    code: str = Field(max_length=16)
    name: str = Field(default="device", min_length=1, max_length=60)
    kind: str = Field(default="other", min_length=1, max_length=20)


def open_window() -> dict:
    """Open a window and say so where the person at the Mac is looking, for the CLI and utt."""
    opened = window.open_window()
    log.info("pairing window open for %d s", window.LASTS)
    plugin.status(pairing=f"code {window.spaced(opened.code)}, for {window.LASTS // 60} minutes")
    return {"code": opened.code, "expires": int(opened.closes), "seconds": window.LASTS}


@router.post("/pair/open", dependencies=[Depends(require_mac)])
def open_pairing() -> dict:
    """A six-digit code, good once for `window.LASTS` seconds; replaces any code already open."""
    return open_window()


@router.post("/pair/transcribe", dependencies=[Depends(require_mac)])
def mint_transcribe(name: str = Query(default="browser", min_length=1, max_length=60)) -> dict:
    """A token that can call `POST /transcribe` and nothing else, for a web page's mic button.
    Minted here rather than paired: the person at the Mac asks for it, so there is no code."""
    token, device = devices.mint(name.strip(), TRANSCRIBE, scope=TRANSCRIBE)
    log.info("minted a transcribe-only token for %s as %s", device["name"], device["id"])
    return {"token": token, "device": device}


@router.post("/pair/manager", dependencies=[Depends(require_mac)])
def mint_manager(name: str = Query(default="mcp", min_length=1, max_length=60)) -> dict:
    """A token that can reach `/mcp`, the manager's tools, and nothing else — for an MCP client
    off this Mac. Minted like the transcribe one: the person at the Mac asks for it."""
    token, device = devices.mint(name.strip(), MANAGER, scope=MANAGER)
    log.info("minted a manager-only token for %s as %s", device["name"], device["id"])
    return {"token": token, "device": device}


@router.post("/pair")
def pair(asking: Asking, request: Request) -> dict:
    """Trade the code on the Mac's screen for a token of this device's own."""
    who = request.client.host if request.client else "?"
    try:
        window.take(asking.code)
    except window.Refused as refused:
        log.warning("pairing refused from %s: %s", who, refused.detail)
        raise HTTPException(status_code=refused.status, detail=refused.detail) from None
    token, device = devices.mint(asking.name.strip(), asking.kind.strip())
    log.info("paired %s (%s) from %s as %s", device["name"], device["kind"], who, device["id"])
    plugin.status(pairing=f"paired {device['name']}")
    return {"token": token, "device": device,
            "mac": {"id": config.machine_id(), "name": beacon.machine_name()}}


@router.get("/pair/check")
def check(x_deckhand_token: str = Header(default="")) -> dict:
    """200 for any token this Mac accepts, 401 for anything else. For the NAS Caddy's
    `forward_auth`, so a device token works off the home network without the edge holding a
    literal of its own."""
    if not allows(x_deckhand_token):
        raise HTTPException(status_code=401, detail="bad token")
    return {"ok": True}


@router.get("/devices", dependencies=[Depends(require_mac)])
def listing() -> dict:
    """Every device paired with a code: id, name, kind, when it paired, when it was last heard."""
    return {"devices": devices.listing()}


def require_device(x_deckhand_token: str = Header(default="")) -> dict:
    """A device paired by code, with no scope: the only caller that may file a key.

    Never this Mac's token. Every agent on the Mac can read that file, so a key filed with it
    would be a key any of them could have filed, and it would prove nothing about who tapped.
    """
    if x_deckhand_token and secrets.compare_digest(x_deckhand_token, config.token()):
        raise HTTPException(status_code=403, detail={
            "code": "NOT_A_DEVICE", "error": "pair this phone by code to answer decisions"})
    device = devices.known(x_deckhand_token)
    if device is None:
        raise HTTPException(status_code=401, detail="bad token")
    if "scope" in device:
        raise HTTPException(status_code=403, detail={
            "code": "NOT_A_DEVICE", "error": f"a {device['scope']}-only token holds no key"})
    return device


class Keying(BaseModel):
    publicKey: str = Field(max_length=200)


@router.put("/devices/key")
def file_key(keying: Keying, device: Annotated[dict, Depends(require_device)]) -> dict:
    """The phone's public signing key, filed on its own row. First key wins.

    The same key again is 200, so the phone can send it on every launch. A different one is 409:
    swapping the key is what an attacker holding this device's token would do, so it takes a
    re-pair — revoking the row on the Mac takes the key with it.
    """
    raw = proofs.key_from(keying.publicKey)
    if raw is None:
        raise HTTPException(status_code=400, detail={
            "code": "BAD_KEY", "error": "publicKey is not a base64 P-256 point (x963, 65 bytes)"})
    said = base64.b64encode(raw).decode()
    if device.get("key") not in (None, said):
        raise HTTPException(status_code=409, detail={
            "code": "KEY_TAKEN", "error": "re-pair to change the key",
            "fingerprint": device.get("fingerprint")})
    if device.get("key") is None:
        devices.give_key(device["id"], said, proofs.fingerprint(raw))
        log.info("%s filed its signing key %s", device["name"], proofs.fingerprint(raw))
    return {"registered": True, "fingerprint": proofs.fingerprint(raw)}


@router.get("/devices/key")
def read_key(device: Annotated[dict, Depends(require_device)]) -> dict:
    """Whether the calling device has filed a key, and its fingerprint."""
    return {"registered": bool(device.get("key")), "fingerprint": device.get("fingerprint")}


@router.delete("/devices/{device_id}", status_code=204, dependencies=[Depends(require_mac)])
def forget(device_id: str) -> None:
    """Take one device's token away. It stops working on its next request; no other changes."""
    gone = devices.forget(device_id)
    if gone is None:
        raise HTTPException(status_code=404, detail=f"no device {device_id}")
    log.info("unpaired %s (%s)", gone["name"], gone["id"])
