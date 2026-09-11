#!/usr/bin/env python3
"""Local integration stub / collector (docs/devops-single-image.md §5).

Stands in for every external integration this world must never actually reach: VAST tag/wrapper
retrieval, impression/tracking beacons, generic webhooks/Slack calls. Deliberately dependency-free
(stdlib only) so it needs no separate build step or package install.

Contract (spec, verbatim): "The local integration stub must expose a health endpoint and log
deterministic requests for hidden verification. It must not proxy unknown URLs. A fallback that
reaches the public internet after a local miss is prohibited."

- `GET /health` -> 200, `{"status": "ok"}`.
- Every other request is logged (method, path, headers, body) as one JSON line to
  `/var/log/local-stub/requests.log` and answered locally — this process never makes an outbound
  network call of its own, so "not proxying unknown URLs" is true by construction, not by a
  denylist that could have gaps.
- Unrecognized paths still get a deterministic 200 acknowledgement (not a 404/502 that could read
  as "try the real endpoint instead") so a caller that doesn't check the response body can't
  accidentally fall through to a real fallback elsewhere.
"""
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG_PATH = "/var/log/local-stub/requests.log"


class StubHandler(BaseHTTPRequestHandler):
    server_version = "LocalIntegrationStub/1.0"

    def _log_request_line(self, body: bytes) -> None:
        entry = {
            "ts": time.time(),
            "method": self.command,
            "path": self.path,
            "headers": dict(self.headers.items()),
            "body": body.decode("utf-8", errors="replace") if body else "",
        }
        with open(LOG_PATH, "a") as f:
            f.write(json.dumps(entry, sort_keys=True) + "\n")

    def _read_body(self) -> bytes:
        length = int(self.headers.get("Content-Length", 0) or 0)
        return self.rfile.read(length) if length else b""

    def _respond_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._respond_json(200, {"status": "ok"})
            return
        self._log_request_line(b"")
        self._respond_json(200, {"status": "ok", "stub": True, "path": self.path})

    def do_POST(self):
        body = self._read_body()
        self._log_request_line(body)
        self._respond_json(200, {"status": "ok", "stub": True, "path": self.path})

    do_PUT = do_POST
    do_DELETE = do_GET

    def log_message(self, fmt, *args):  # noqa: A003 - stdlib override
        # Suppress the default stderr access log; requests.log is the deterministic record.
        pass


if __name__ == "__main__":
    import os

    os.makedirs("/var/log/local-stub", exist_ok=True)
    server = ThreadingHTTPServer(("0.0.0.0", 9080), StubHandler)
    server.serve_forever()
