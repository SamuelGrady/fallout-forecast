"""Fallout Forecast telemetry collector.

Accepts POST /v1/events with one JSON event per request (the game sends
text/plain so browsers skip the CORS preflight) and appends it, with a server
timestamp, to /data/events-YYYY-MM-DD.jsonl. Write-only from the internet:
there is no read endpoint; read the JSONL files directly from the data volume.

Limits: 64 KB per event, 120 events per IP per 10 minutes, and the data
directory is capped (oldest day files deleted past MAX_TOTAL_BYTES). Client IPs
are used only for the in-memory rate limit and never written.
Standard library only.
"""
import json
import os
import threading
import time
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DATA = os.environ.get("TELEMETRY_DIR", "/data")
PORT = int(os.environ.get("PORT", "8080"))
MAX_BODY = 64 * 1024
RATE_WINDOW = 600.0
RATE_MAX = 120
MAX_TOTAL_BYTES = int(os.environ.get("MAX_TOTAL_BYTES", str(2 * 1024**3)))
KINDS = {"session", "perf", "run_start", "run_end"}

_lock = threading.Lock()
_hits = defaultdict(deque)
_last_prune = 0.0


def _allowed(ip):
    now = time.monotonic()
    with _lock:
        q = _hits[ip]
        while q and now - q[0] > RATE_WINDOW:
            q.popleft()
        if len(q) >= RATE_MAX:
            return False
        q.append(now)
        if len(_hits) > 10000:
            for key in [k for k, v in _hits.items() if not v]:
                del _hits[key]
        return True


def _prune():
    global _last_prune
    if time.monotonic() - _last_prune < 300:
        return
    _last_prune = time.monotonic()
    files = sorted(f for f in os.listdir(DATA) if f.startswith("events-") and f.endswith(".jsonl"))
    total = sum(os.path.getsize(os.path.join(DATA, f)) for f in files)
    while files and total > MAX_TOTAL_BYTES:
        oldest = files.pop(0)
        total -= os.path.getsize(os.path.join(DATA, oldest))
        os.remove(os.path.join(DATA, oldest))


class Handler(BaseHTTPRequestHandler):
    server_version = "fallout-telemetry"
    sys_version = ""

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Max-Age", "86400")

    def _reply(self, code, body=b""):
        self.send_response(code)
        self._cors()
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_OPTIONS(self):
        self._reply(204)

    def do_GET(self):
        if self.path in ("/", "/health"):
            self._reply(200, b"ok\n")
        else:
            self._reply(404)

    def do_POST(self):
        if self.path != "/v1/events":
            return self._reply(404)
        ip = self.headers.get("X-Forwarded-For", self.client_address[0]).split(",")[0].strip()
        if not _allowed(ip):
            return self._reply(429)
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return self._reply(400)
        if length <= 0 or length > MAX_BODY:
            return self._reply(413)
        try:
            event = json.loads(self.rfile.read(length))
        except (ValueError, UnicodeDecodeError):
            return self._reply(400)
        if not isinstance(event, dict) or event.get("kind") not in KINDS:
            return self._reply(400)
        install = str(event.get("install", ""))
        if len(install) > 64 or len(str(event.get("session", ""))) > 64:
            return self._reply(400)
        event["received"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        line = json.dumps(event, separators=(",", ":")) + "\n"
        name = os.path.join(DATA, "events-%s.jsonl" % time.strftime("%Y-%m-%d", time.gmtime()))
        with _lock:
            with open(name, "a", encoding="utf-8") as f:
                f.write(line)
            _prune()
        self._reply(204)

    def log_message(self, *args):
        pass  # no access logs: they would hold IPs


if __name__ == "__main__":
    os.makedirs(DATA, exist_ok=True)
    print("fallout-telemetry listening on", PORT, "->", DATA, flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
