"""WebSocket event fan-out and progress-file tailing."""

from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path
from typing import Any

log = logging.getLogger(__name__)


class EventHub:
    """Broadcasts JSON events to every connected WebSocket client."""

    def __init__(self) -> None:
        self._clients: set[asyncio.Queue[dict[str, Any]]] = set()

    def subscribe(self) -> asyncio.Queue[dict[str, Any]]:
        q: asyncio.Queue[dict[str, Any]] = asyncio.Queue()
        self._clients.add(q)
        return q

    def unsubscribe(self, q: asyncio.Queue[dict[str, Any]]) -> None:
        self._clients.discard(q)

    def publish(self, event: dict[str, Any]) -> None:
        for q in list(self._clients):
            q.put_nowait(event)


async def tail_progress(path: Path, hub: EventHub, interval: float = 0.1) -> None:
    """Forward JSON lines that MATLAB appends to ``path`` as hub events.

    MATLAB can't be queried while it is busy planning a trip, so it writes
    progress ("Checking the route to Oulu.") to this file instead.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("", encoding="utf-8")
    position = 0
    while True:
        await asyncio.sleep(interval)
        try:
            with path.open("r", encoding="utf-8") as f:
                f.seek(position)
                chunk = f.read()
                position = f.tell()
        except OSError:
            continue
        for line in chunk.splitlines():
            if line.strip():
                try:
                    hub.publish(json.loads(line))
                except json.JSONDecodeError:
                    log.warning("Ignoring malformed progress line: %r", line)
