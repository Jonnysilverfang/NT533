import json
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


SERVICE_NAME = os.getenv("SERVICE_NAME", "service")
PORT = int(os.getenv("PORT", "8080"))
DB_HOST = os.getenv("DB_HOST", "")
DB_PORT = int(os.getenv("DB_PORT", "5432"))


def database_tcp_ready():
    """Use a bounded TCP probe so ALB health remains gated on restored RDS."""
    if not DB_HOST:
        return True, "not-configured"
    try:
        with socket.create_connection((DB_HOST, DB_PORT), timeout=2):
            return True, "reachable"
    except OSError:
        return False, "unreachable"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            ready, database = database_tcp_ready()
            self._reply(
                200 if ready else 503,
                {"status": "healthy" if ready else "unhealthy", "service": SERVICE_NAME, "database": database},
            )
            return

        expected = f"/{SERVICE_NAME}"
        if self.path == expected or self.path.startswith(f"{expected}/"):
            self._reply(200, {"service": SERVICE_NAME, "region": os.getenv("AWS_REGION", "unknown")})
            return

        self._reply(404, {"error": "not found"})

    def log_message(self, format_string, *args):
        print(json.dumps({"service": SERVICE_NAME, "message": format_string % args}))

    def _reply(self, status, body):
        payload = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
