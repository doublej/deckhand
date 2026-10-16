"""A stand-in for the OpenCode service, behind the one seam every OpenCode call goes through.

Shaped off what OpenCode 2.0.31 answered on 2026-10-16: the envelope (`data`, `cursor`), the
session and message records, millisecond times, and an error that is a sentence.
"""

import time

from deckhand_daemon.sessions import opencode

SHOP = "/Users/jj/dev/web/shop"
NOW = time.time() * 1000


def info(session_id, title="", updated=NOW, parent=None, archived=None, folder=SHOP):
    times = {"created": updated - 60_000, "updated": updated}
    if archived:
        times["archived"] = archived
    found = {"id": session_id, "projectID": "p", "cost": 0, "time": times,
             "tokens": {"input": 0, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
             "location": {"directory": folder}, "agent": "build",
             "model": {"id": "claude-opus-5-5", "providerID": "anthropic", "variant": "xhigh"}}
    if title:
        found["title"] = title
    if parent:
        found["parentID"] = parent
    return found


class FakeOpenCode:
    """Sessions, their messages and inboxes, and every call made, answered as the service does."""

    def __init__(self):
        self.sessions = {}
        self.active = set()
        self.messages = {}
        self.inbox = {}
        self.permissions = {}
        self.forms = {}
        self.commands = [{"name": "review", "description": "Review the changes"}]
        self.skills = [{"id": "plain-writing", "name": "plain-writing", "content": "",
                        "description": "Plain prose", "path": "/Users/jj/.skills/plain/SKILL.md"}]
        self.models = [{"id": "claude-opus-5-5", "providerID": "anthropic",
                        "limit": {"context": 1_000_000, "output": 128_000}}]
        self.calls = []

    def add(self, record, busy=False, messages=()):
        self.sessions[record["id"]] = record
        if busy:
            self.active.add(record["id"])
        self.messages[record["id"]] = list(messages)
        return record

    def request(self, method, path, body=None, *, query=None, timeout=None):
        self.calls.append((method, path, body, query))
        query = query or {}
        parts = path.removeprefix("/api/").split("/")
        if parts == ["session", "active"]:
            return {"data": {sid: {"type": "running"} for sid in self.active}}
        if parts == ["session"] and method == "GET":
            parent = query.get("parentID")
            rows = [s for s in self.sessions.values()
                    if s.get("parentID") == (None if parent == "null" else parent)]
            rows.sort(key=lambda s: s["time"]["updated"], reverse=True)
            return {"data": rows[: int(query.get("limit") or 50)], "cursor": {"next": None}}
        if parts == ["session"] and method == "POST":
            made = info("ses_new0000fresh", updated=NOW, folder=body["location"]["directory"])
            return {"data": self.add(made)}
        if parts in (["command"], ["skill"], ["model"]):
            return {"data": {"command": self.commands, "skill": self.skills,
                             "model": self.models}[parts[0]]}
        if parts[0] != "session" or parts[1] not in self.sessions:
            raise opencode.OpenCodeError(f"Session not found: {parts[1] if len(parts) > 1 else ''}")
        return self._session(method, parts[1], parts[2:], body, query)

    def _session(self, method, sid, rest, body, query):
        if not rest:
            if method == "PATCH":
                self.sessions[sid]["title"] = body["title"]
                return {}
            return {"data": self.sessions[sid]}
        verb = rest[0]
        if verb == "message":
            found = [m for m in self.messages[sid] if not query.get("type")
                     or m["type"] == query["type"]]
            if query.get("order") == "desc":
                found = list(reversed(found))
            return {"data": found[: int(query.get("limit") or 100)], "cursor": {"next": None}}
        if verb == "inbox":
            if method == "DELETE":
                self.inbox[sid] = [i for i in self.inbox.get(sid, []) if i["id"] != rest[1]]
                return {}
            return {"data": self.inbox.get(sid, [])}
        if verb in ("permission", "form"):
            return {"data": (self.permissions if verb == "permission" else self.forms).get(sid, [])}
        if verb == "interrupt":
            return {"interrupted": sid in self.active}
        if verb == "command" and body["name"] not in {c["name"] for c in self.commands}:
            raise opencode.OpenCodeError(f"Command not found: {body['name']}")
        return {"data": {"id": "msg_x", "sessionID": sid, "type": verb}}
