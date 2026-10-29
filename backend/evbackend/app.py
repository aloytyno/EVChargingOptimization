"""HTTP + WebSocket API for the EV assistant UI.

Run with ``uvicorn evbackend.app:app`` (see ``run.ps1``). The routes are thin:
each one forwards to a command of the MATLAB function ``evcharge.api.request``.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
import os
import tempfile
from pathlib import Path
from typing import Any

from fastapi import Body, FastAPI, WebSocket, WebSocketDisconnect
from pydantic import BaseModel

from .bridge import Bridge, MatlabBridge
from .events import EventHub, tail_progress

log = logging.getLogger(__name__)

PROJECT_ROOT = Path(__file__).resolve().parents[2]


class AskBody(BaseModel):
    text: str


def create_app(bridge: Bridge, progress_file: Path | None = None) -> FastAPI:
    hub = EventHub()
    background: set[asyncio.Task] = set()

    @contextlib.asynccontextmanager
    async def lifespan(_: FastAPI):
        tasks = []
        if progress_file is not None:
            tasks.append(asyncio.create_task(tail_progress(progress_file, hub)))
        bridge.start()
        yield
        for task in tasks:
            task.cancel()

    api = FastAPI(title="EV Assistant API", lifespan=lifespan)
    api.state.hub = hub

    def spawn(coro) -> None:
        task = asyncio.create_task(coro)
        background.add(task)
        task.add_done_callback(background.discard)

    async def busy_call(command: str, **args: Any):
        hub.publish({"type": "busy", "command": command})
        try:
            return await bridge.call(command, **args)
        finally:
            hub.publish({"type": "idle"})

    async def speak(text: str) -> None:
        hub.publish({"type": "speaking", "on": True})
        try:
            await bridge.call("speak", text=text, interrupt=False)
        finally:
            hub.publish({"type": "speaking", "on": False})

    @api.get("/health")
    async def health():
        if bridge.startup_error:
            return {"ok": False, "starting": False, "error": bridge.startup_error}
        if not bridge.ready:
            return {"ok": False, "starting": True}
        result = await bridge.call("health")
        return {"starting": False, **result}

    @api.get("/state")
    async def get_state():
        return await bridge.call("getState")

    @api.patch("/state")
    async def patch_state(changes: dict[str, Any] = Body(...)):
        state = await busy_call("setState", **changes)
        if "error" not in state:
            hub.publish({"type": "stateChanged", "state": state})
        return state

    @api.get("/vehicles")
    async def vehicles():
        return await bridge.call("listVehicles")

    @api.get("/locations")
    async def locations():
        return await bridge.call("listLocations")

    @api.get("/plan")
    async def plan():
        return await bridge.call("getPlan")

    @api.post("/ask")
    async def ask(body: AskBody):
        result = await busy_call("ask", text=body.text)
        if isinstance(result, dict) and "state" in result:
            hub.publish({"type": "stateChanged", "state": result["state"]})
        # Return the text right away; speech is synthesized afterwards.
        if isinstance(result, dict) and result.get("reply") and _speech_enabled():
            spawn(speak(result["reply"]))
        return result

    @api.post("/listen/start")
    async def listen_start():
        result = await bridge.call("startListening")
        if "error" not in result:
            hub.publish({"type": "listening", "on": True})
        return result

    @api.post("/listen/stop")
    async def listen_stop():
        hub.publish({"type": "listening", "on": False})
        return await busy_call("stopListening")

    @api.post("/speak/stop")
    async def speak_stop():
        return await bridge.call("stopSpeaking")

    @api.post("/reset")
    async def reset():
        return await bridge.call("reset")

    @api.websocket("/events")
    async def events(ws: WebSocket):
        await ws.accept()
        q = hub.subscribe()
        try:
            while True:
                await ws.send_json(await q.get())
        except WebSocketDisconnect:
            pass
        finally:
            hub.unsubscribe(q)

    return api


def _speech_enabled() -> bool:
    return os.environ.get("EV_SPEECH", "1") != "0"


def _env_flag(name: str, default: bool) -> bool:
    value = os.environ.get(name)
    return default if value is None else value not in ("0", "false", "False")


def _default_app() -> FastAPI:
    logging.basicConfig(level=logging.INFO)
    progress = Path(tempfile.gettempdir()) / "evcharge_progress.jsonl"
    bridge = MatlabBridge(
        PROJECT_ROOT,
        progress,
        use_live_data=_env_flag("EV_LIVE_DATA", True),
        speech=_speech_enabled(),
        shared_session=os.environ.get("EV_MATLAB_SESSION"),
    )
    return create_app(bridge, progress)


app = _default_app()
