"""The pairing routes: one open to the LAN, the rest for this Mac alone.

`POST /pair` is the only route besides `/health` that answers without a token, and it does
nothing at all unless the person at the Mac has opened a window (`window.py`). Everything that
opens a window or lists or revokes devices needs **this Mac's own token** — a paired phone holds
a device token and gets a 403 here, so no device can open a window for another or revoke a
sibling.
"""

from __future__ import annotations

import secrets

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, Field

from .. import beacon, config, plugin
from ..log import log
from . import allows, devices, window

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


@router.delete("/devices/{device_id}", status_code=204, dependencies=[Depends(require_mac)])
def forget(device_id: str) -> None:
    """Take one device's token away. It stops working on its next request; no other changes."""
    gone = devices.forget(device_id)
    if gone is None:
        raise HTTPException(status_code=404, detail=f"no device {device_id}")
    log.info("unpaired %s (%s)", gone["name"], gone["id"])
