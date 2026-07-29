#!/usr/bin/env python3
"""Dummy stand-in for a real vLLM model server (demo.md section 3/5).

Does no real inference - it only exposes the shape a real model-serving
pod has: liveness/readiness probes and a request-queue-depth metric.
This lets KubeAI treat it as a normal scalable workload without needing
real GPUs or model weights.
"""
import os
import random
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("PORT", "8000"))

# Fake queue depth, drifting like real request load would, so a metric
# consumer (Prometheus/KubeAI) sees varying rather than flat numbers.
queue_depth = 0.0


def drift_queue_depth():
    global queue_depth
    while True:
        queue_depth = max(0, queue_depth + random.uniform(-2, 3))
        time.sleep(2)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/healthz", "/readyz"):
            self._respond(200, b"ok")
        elif self.path == "/metrics":
            body = (
                "# HELP fake_vllm_queue_depth Pending requests in the fake queue\n"
                "# TYPE fake_vllm_queue_depth gauge\n"
                f"fake_vllm_queue_depth {queue_depth:.1f}\n"
            ).encode()
            self._respond(200, body, content_type="text/plain; version=0.0.4")
        else:
            self._respond(404, b"not found")

    def _respond(self, status, body, content_type="text/plain"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    import threading

    threading.Thread(target=drift_queue_depth, daemon=True).start()
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
