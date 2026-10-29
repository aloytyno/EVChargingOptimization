"""Bridge between the HTTP API and the MATLAB backend.

All MATLAB work goes through ``evcharge.api.request`` (a JSON-in/JSON-out
function), executed by one worker thread that owns the MATLAB engine. The
engine is not thread-safe, so calls are serialized through a queue.
"""

from __future__ import annotations

import asyncio
import json
import logging
import queue
import threading
from concurrent.futures import Future
from pathlib import Path
from typing import Any, Protocol

log = logging.getLogger(__name__)


class Bridge(Protocol):
    """What the API needs from a backend; tests provide a fake."""

    ready: bool
    startup_error: str | None

    def start(self) -> None: ...

    async def call(self, command: str, **args: Any) -> dict[str, Any] | list[Any]: ...


class MatlabBridge:
    """Runs ``evcharge.api.request`` in a MATLAB engine on a worker thread."""

    def __init__(
        self,
        project_root: Path,
        progress_file: Path,
        *,
        use_live_data: bool = True,
        speech: bool = True,
        shared_session: str | None = None,
    ) -> None:
        self.project_root = project_root
        self.progress_file = progress_file
        self.use_live_data = use_live_data
        self.speech = speech
        self.shared_session = shared_session
        self.ready = False
        self.startup_error: str | None = None
        self._jobs: queue.Queue[tuple[dict[str, Any], Future]] = queue.Queue()
        self._thread = threading.Thread(target=self._run, name="matlab", daemon=True)

    def start(self) -> None:
        self._thread.start()

    async def call(self, command: str, **args: Any) -> dict[str, Any] | list[Any]:
        if self.startup_error:
            return {"error": f"MATLAB backend failed to start: {self.startup_error}"}
        future: Future = Future()
        self._jobs.put(({"command": command, **args}, future))
        return await asyncio.wrap_future(future)

    # -- worker thread ---------------------------------------------------

    def _run(self) -> None:
        try:
            engine = self._connect()
            engine.cd(str(self.project_root), nargout=0)
            engine.addProjectPaths(nargout=0)
            init = {
                "command": "init",
                "progressFile": str(self.progress_file),
                "useLiveData": self.use_live_data,
                "speech": self.speech,
            }
            health = self._request(engine, init)
            log.info("MATLAB backend ready: %s", health)
            self.ready = True
        except Exception as exc:  # noqa: BLE001 - reported through /health
            log.exception("MATLAB backend failed to start")
            self.startup_error = str(exc)
            self._fail_pending()
            return

        while True:
            request, future = self._jobs.get()
            if future.set_running_or_notify_cancel():
                try:
                    future.set_result(self._request(engine, request))
                except Exception as exc:  # noqa: BLE001
                    future.set_result({"error": f"MATLAB call failed: {exc}"})

    def _connect(self):
        import matlab.engine  # Imported here so tests don't need MATLAB.

        names = matlab.engine.find_matlab()
        if self.shared_session and self.shared_session in names:
            log.info("Connecting to shared MATLAB session %s", self.shared_session)
            return matlab.engine.connect_matlab(self.shared_session)
        if names and self.shared_session is None:
            log.info("Connecting to shared MATLAB session %s", names[0])
            return matlab.engine.connect_matlab(names[0])
        log.info("Starting a new MATLAB engine (this takes a while)")
        return matlab.engine.start_matlab("-nodesktop")

    @staticmethod
    def _request(engine, request: dict[str, Any]) -> Any:
        response = engine.feval("evcharge.api.request", json.dumps(request), nargout=1)
        return json.loads(response)

    def _fail_pending(self) -> None:
        while not self._jobs.empty():
            _, future = self._jobs.get_nowait()
            future.set_result({"error": f"MATLAB backend failed to start: {self.startup_error}"})
