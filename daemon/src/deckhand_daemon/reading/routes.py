"""The subagents a session has started, and one of their conversations.

Two routes, and they are the same two the session itself has — a listing and a page of turns —
because a subagent *is* a conversation and pretending otherwise is what made them look like tool
calls in the first place.

A router rather than lines in `app.py` for the reason `links/` and `projects/` are routers: the
hand mounts this whole file unchanged. A subagent's transcript is a file on the disk of whichever
machine ran it, which is exactly the kind of thing a hand is for, and a second copy of this
reading would be a second answer able to drift from the first.
"""

from __future__ import annotations

import asyncio

from fastapi import APIRouter, HTTPException, Query

from ..sessions import live_sessions
from . import agents

router = APIRouter(tags=["agents"])


def _live_or_404(session_id: str) -> None:
    """The same refusal `/turns` makes, spelled here because this router is mounted on two apps
    that reach a session in two different ways."""
    if not any(s.session_id == session_id for s in live_sessions(paned_only=False)):
        raise HTTPException(status_code=404, detail="no such live session")


@router.get("/sessions/{session_id}/agents")
async def session_agents(session_id: str) -> dict:
    """Every subagent this session has started, newest first, and whether each is still going.

    Answered on the same poll that draws the conversation: it is a directory listing and a few
    small JSON reads, and a screen that had to ask separately would show a session's agents a beat
    after the turn that started them.
    """
    await asyncio.to_thread(_live_or_404, session_id)
    found = await asyncio.to_thread(agents.spawned, session_id)
    return {"agents": [agent.to_json() for agent in found]}


@router.get("/sessions/{session_id}/agents/{agent_id}/turns")
async def agent_turns(
    session_id: str,
    agent_id: str,
    limit: int = Query(default=8, ge=1, le=200),
    before: int = Query(default=0, ge=0, description="how many turns from the end to skip"),
) -> dict:
    """One subagent's own conversation, paged exactly as the session's is.

    No `queued`: nothing can speak to a subagent. It has no inbox socket, no record in
    `~/.claude/sessions/`, and no name anything could address — it is a conversation the session
    is having, not a session of its own, and the one honest thing this can offer is reading.
    """
    await asyncio.to_thread(_live_or_404, session_id)
    turns, more = await asyncio.to_thread(agents.read_turns, session_id, agent_id, limit, before)
    return {"turns": [turn.to_json() for turn in turns], "more": more}
