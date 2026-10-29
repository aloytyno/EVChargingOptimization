"""API tests with a fake bridge (no MATLAB needed)."""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient

from evbackend.app import create_app
from evbackend.events import EventHub, tail_progress


class FakeBridge:
    def __init__(self) -> None:
        self.ready = False
        self.startup_error = None
        self.calls: list[tuple[str, dict[str, Any]]] = []
        self.state = {"soc_percent": 72, "location": "Helsinki"}

    def start(self) -> None:
        self.ready = True

    async def call(self, command: str, **args: Any):
        self.calls.append((command, args))
        if command == "health":
            return {"ok": True, "model_ok": True, "speech_ok": True}
        if command == "getState":
            return self.state
        if command == "setState":
            self.state = {**self.state, **args}
            return self.state
        if command == "ask":
            return {"reply": "You can make it.", "tools_called": ["plan_trip"],
                    "plan": {"stops": []}, "state": self.state}
        if command == "stopListening":
            return {"transcript": "Take me to Oulu"}
        return {"ok": True}


@pytest.fixture
def bridge() -> FakeBridge:
    return FakeBridge()


@pytest.fixture
def client(bridge: FakeBridge):
    with TestClient(create_app(bridge)) as c:
        yield c


def test_health_after_start(client: TestClient) -> None:
    body = client.get("/health").json()
    assert body["ok"] is True
    assert body["starting"] is False


def test_health_while_starting() -> None:
    bridge = FakeBridge()
    bridge.start = lambda: None  # Engine still starting.
    with TestClient(create_app(bridge)) as c:
        assert c.get("/health").json() == {"ok": False, "starting": True}


def test_patch_state_forwards_fields(client: TestClient, bridge: FakeBridge) -> None:
    body = client.patch("/state", json={"soc_percent": 40, "location": "Oulu"}).json()
    assert body["soc_percent"] == 40
    assert ("setState", {"soc_percent": 40, "location": "Oulu"}) in bridge.calls


def test_ask_returns_reply_then_speaks(client: TestClient, bridge: FakeBridge) -> None:
    body = client.post("/ask", json={"text": "Take me to Oulu"}).json()
    assert body["reply"] == "You can make it."
    commands = [c for c, _ in bridge.calls]
    assert commands.index("ask") < commands.index("speak")
    speak_args = dict(bridge.calls)["speak"]
    assert speak_args == {"text": "You can make it.", "interrupt": False}


def test_listen_flow(client: TestClient) -> None:
    assert client.post("/listen/start").json() == {"ok": True}
    assert client.post("/listen/stop").json()["transcript"] == "Take me to Oulu"


def test_events_websocket_reports_busy_and_state(client: TestClient) -> None:
    with client.websocket_connect("/events") as ws:
        client.patch("/state", json={"soc_percent": 50})
        events = [ws.receive_json() for _ in range(3)]
    types = [e["type"] for e in events]
    assert types == ["busy", "idle", "stateChanged"]
    assert events[2]["state"]["soc_percent"] == 50


def test_progress_file_lines_become_events(tmp_path: Path) -> None:
    async def scenario():
        hub = EventHub()
        q = hub.subscribe()
        path = tmp_path / "progress.jsonl"
        task = asyncio.create_task(tail_progress(path, hub, interval=0.01))
        await asyncio.sleep(0.05)
        with path.open("a", encoding="utf-8") as f:
            f.write(json.dumps({"type": "progress", "text": "Checking the route to Oulu."}) + "\n")
        event = await asyncio.wait_for(q.get(), timeout=2)
        task.cancel()
        return event

    event = asyncio.run(scenario())
    assert event == {"type": "progress", "text": "Checking the route to Oulu."}
