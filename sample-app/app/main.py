"""hello-app: the tiny service that the CI/CD pipeline builds, tests and deploys.

Standard library only, so the pipeline needs no pip/PyPI access.
"""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "1.0.0"
HOST = "0.0.0.0"
PORT = int(os.environ.get("PORT", "8080"))


def greeting(name: str = "world") -> str:
    return f"Hello, {name}!"


class Handler(BaseHTTPRequestHandler):
    def _send(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 (stdlib naming)
        if self.path == "/":
            self._send(200, {
                "message": greeting("DevOps"),
                "version": VERSION,
                "commit": os.environ.get("GIT_SHA", "unknown"),
            })
        elif self.path == "/healthz":
            self._send(200, {"status": "ok", "version": VERSION})
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, fmt, *args) -> None:  # quieter logs
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"hello-app {VERSION} listening on {HOST}:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
