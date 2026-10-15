"""The headset's camera over the wire: one JPEG at a time in, MJPEG out, and how many are watching.

The camera is a thing the person puts in the headset's space and aims by hand (`deckhand-xr`,
`quest/…/camera/`). The headset draws what it sees there itself — the planes, never the room or
the person, who are not in the scene — and posts each picture here. `docs/space.md`, *The camera*,
is the long version.

**A viewer is what asks for the stream.** The headset streams only while someone watches here or
the person switched streaming on, and never silently: it reads `viewers` off `GET /camera` while
it is not streaming, and off every `POST /camera/frames` while it is, so the last viewer leaving
stops it within a frame. Counting is the stream's own business: a viewer is counted from its first
byte to its disconnect.

**One picture, the newest.** A frame replaces the last and wakes every viewer, each of which sends
whatever is newest when it gets there; a slow viewer skips pictures rather than queueing them.
Nothing is written to disk. A new viewer gets the last picture at once, so a still camera is a
picture and not a blank, and `live` says whether it is still coming.

No token check of its own: it rides `routes.py`'s router, as `/windows` does.
"""

from __future__ import annotations

import asyncio
import contextlib
import time
from collections.abc import AsyncIterator, Awaitable, Callable

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import StreamingResponse

router = APIRouter(tags=["camera"])

#: The parts' separator, the one `deckhand-windows` uses for its own MJPEG.
BOUNDARY = "frame"
#: A picture this old says the camera stopped: `live` is false.
LIVE_S = 2.0
#: How often a viewer with nothing new looks whether it is still there.
WAKE_S = 5.0
#: A 1280 × 720 JPEG is ~100 kB; this is a body that is not a camera frame.
MAX_BYTES = 2_000_000
SOI = b"\xff\xd8"


class Feed:
    """The newest picture, its number and when it came, and who is watching."""

    def __init__(self) -> None:
        self.jpeg = b""
        self.seq = 0
        self.at = 0.0
        self.viewers = 0
        self.arrived = asyncio.Event()

    def put(self, jpeg: bytes) -> None:
        """Keep `jpeg` as the newest and wake every viewer waiting for one."""
        self.jpeg, self.seq, self.at = jpeg, self.seq + 1, time.time()
        woken, self.arrived = self.arrived, asyncio.Event()
        woken.set()

    def state(self) -> dict:
        return {
            "live": self.seq > 0 and time.time() - self.at < LIVE_S,
            "viewers": self.viewers,
            "at": self.at or None,
        }


feed = Feed()


def part(jpeg: bytes) -> bytes:
    head = f"--{BOUNDARY}\r\nContent-Type: image/jpeg\r\nContent-Length: {len(jpeg)}\r\n\r\n"
    return head.encode() + jpeg + b"\r\n"


async def parts(feed: Feed, gone: Callable[[], Awaitable[bool]]) -> AsyncIterator[bytes]:
    """Every picture as it comes, the newest first; counted as a viewer until `gone()` says so
    or the stream is closed under it."""
    feed.viewers += 1
    try:
        seen = 0
        while True:
            if feed.seq != seen:
                seen = feed.seq
                yield part(feed.jpeg)
                continue
            # A viewer that left while no picture came would otherwise be counted until the next
            # one, and a ghost viewer starts the headset's stream.
            with contextlib.suppress(TimeoutError):
                await asyncio.wait_for(feed.arrived.wait(), WAKE_S)
            if feed.seq == seen and await gone():
                return
    finally:
        feed.viewers -= 1


@router.get("/camera")
async def camera() -> dict:
    """`{live, viewers, at}`: whether a picture came in the last two seconds, how many watch
    `/camera/stream` now, and when the last picture came (epoch seconds, null for none yet)."""
    return feed.state()


@router.post("/camera/frames")
async def camera_frame(request: Request) -> dict:
    """One JPEG as the whole body → `{viewers}`. The headset's to call, once per picture, while
    someone watches or the person switched streaming on; `viewers` falling to 0 is its cue to stop
    unless they did."""
    jpeg = await request.body()
    if len(jpeg) > MAX_BYTES:
        raise HTTPException(status_code=413, detail=f"a frame is at most {MAX_BYTES} bytes")
    if not jpeg.startswith(SOI):
        raise HTTPException(status_code=400, detail="a frame is one JPEG")
    feed.put(jpeg)
    return {"viewers": feed.viewers}


@router.get("/camera/stream")
async def camera_stream(request: Request) -> StreamingResponse:
    """The camera as MJPEG (`multipart/x-mixed-replace; boundary=frame`), the last picture first.
    Watching is what asks the headset to stream: it counts in `viewers` until it disconnects."""
    return StreamingResponse(
        parts(feed, request.is_disconnected),
        media_type=f"multipart/x-mixed-replace; boundary={BOUNDARY}",
        headers={"Cache-Control": "no-store"},
    )
