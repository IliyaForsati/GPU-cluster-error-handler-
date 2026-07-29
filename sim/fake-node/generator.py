#!/usr/bin/env python3
"""Fake worker node: pretends to be one physical machine from demo.md.

Runs two things at once, matching the real telemetry agents in
demo.md section 3:
  - an HTTP /metrics endpoint, in the same Prometheus text format
    DCGM exporter uses, for `GPU_COUNT` fake H200 GPUs
  - stdout log lines, in the same shape Fluent Bit tails from a real
    vLLM/container process (normal request logs, plus occasional
    CUDA OOM / NCCL timeout / XID fault lines)

No CUDA and no GPUs are involved - all numbers are made up. The point
is to give Elasticsearch realistic-looking documents to build and test
alert rules against, since the real cluster is not available.
"""
import os
import random
import sys
import threading
import time
import traceback
from http.server import BaseHTTPRequestHandler, HTTPServer

NODE_INDEX = os.environ.get("NODE_INDEX", "0")
GPU_COUNT = int(os.environ.get("GPU_COUNT", "8"))
METRICS_PORT = int(os.environ.get("METRICS_PORT", "9400"))
# Chance, per GPU per log tick, that we emit a fault line instead of a
# normal one. Kept low by default so faults look like real rare events.
FAULT_RATE = float(os.environ.get("FAULT_RATE", "0.03"))
LOG_INTERVAL_SECONDS = float(os.environ.get("LOG_INTERVAL_SECONDS", "3"))

# Real per-GPU state, so metrics drift smoothly instead of jumping
# around randomly on every scrape - closer to how a real GPU behaves.
gpu_state = [
    {
        "temp_c": random.uniform(45, 60),
        "power_w": random.uniform(300, 450),
        "fb_used_mb": random.uniform(20000, 40000),
        "ecc_errors": 0,
        "xid_errors": 0,
    }
    for _ in range(GPU_COUNT)
]


def drift_metrics():
    """Background loop: nudges each fake GPU's metrics over time."""
    while True:
        for gpu in gpu_state:
            gpu["temp_c"] = max(35, min(95, gpu["temp_c"] + random.uniform(-2, 2)))
            gpu["power_w"] = max(100, min(700, gpu["power_w"] + random.uniform(-15, 15)))
            gpu["fb_used_mb"] = max(0, min(141000, gpu["fb_used_mb"] + random.uniform(-500, 500)))
            # ECC/XID counters only ever go up, like real hardware counters,
            # and only increment when a fault is injected (see emit_fault).
        time.sleep(1)


class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return

        lines = [
            "# HELP DCGM_FI_DEV_GPU_TEMP GPU temperature in Celsius",
            "# TYPE DCGM_FI_DEV_GPU_TEMP gauge",
        ]
        for idx, gpu in enumerate(gpu_state):
            labels = f'node_index="{NODE_INDEX}",gpu="{idx}",modelName="H200"'
            lines.append(f"DCGM_FI_DEV_GPU_TEMP{{{labels}}} {gpu['temp_c']:.1f}")
        lines += [
            "# HELP DCGM_FI_DEV_POWER_USAGE Power draw in Watts",
            "# TYPE DCGM_FI_DEV_POWER_USAGE gauge",
        ]
        for idx, gpu in enumerate(gpu_state):
            labels = f'node_index="{NODE_INDEX}",gpu="{idx}",modelName="H200"'
            lines.append(f"DCGM_FI_DEV_POWER_USAGE{{{labels}}} {gpu['power_w']:.1f}")
        lines += [
            "# HELP DCGM_FI_DEV_FB_USED Framebuffer memory used in MiB",
            "# TYPE DCGM_FI_DEV_FB_USED gauge",
        ]
        for idx, gpu in enumerate(gpu_state):
            labels = f'node_index="{NODE_INDEX}",gpu="{idx}",modelName="H200"'
            lines.append(f"DCGM_FI_DEV_FB_USED{{{labels}}} {gpu['fb_used_mb']:.0f}")
        lines += [
            "# HELP DCGM_FI_DEV_ECC_DBE_VOL_TOTAL Total ECC double-bit volatile errors",
            "# TYPE DCGM_FI_DEV_ECC_DBE_VOL_TOTAL counter",
        ]
        for idx, gpu in enumerate(gpu_state):
            labels = f'node_index="{NODE_INDEX}",gpu="{idx}",modelName="H200"'
            lines.append(f"DCGM_FI_DEV_ECC_DBE_VOL_TOTAL{{{labels}}} {gpu['ecc_errors']}")
        lines += [
            "# HELP DCGM_FI_DEV_XID_ERRORS Count of XID errors",
            "# TYPE DCGM_FI_DEV_XID_ERRORS counter",
        ]
        for idx, gpu in enumerate(gpu_state):
            labels = f'node_index="{NODE_INDEX}",gpu="{idx}",modelName="H200"'
            lines.append(f"DCGM_FI_DEV_XID_ERRORS{{{labels}}} {gpu['xid_errors']}")

        body = ("\n".join(lines) + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass  # don't spam stdout with HTTP access logs


def serve_metrics():
    server = HTTPServer(("0.0.0.0", METRICS_PORT), MetricsHandler)
    server.serve_forever()


def normal_log_line(gpu_idx):
    req_id = random.randint(100000, 999999)
    tokens = random.randint(50, 900)
    latency_ms = random.randint(80, 600)
    print(
        f'{ts()} INFO vllm[node={NODE_INDEX} gpu={gpu_idx}] '
        f'request_id={req_id} tokens={tokens} latency_ms={latency_ms} status=200'
    )


def cuda_oom_line(gpu_idx):
    # Shaped like a real PyTorch CUDA OOM traceback, so Fluent Bit's
    # multiline parsing and future Kibana rules see something realistic.
    print(
        f"{ts()} ERROR vllm[node={NODE_INDEX} gpu={gpu_idx}] "
        f"CUDA out of memory. Tried to allocate 2.14 GiB "
        f"(GPU {gpu_idx}; 140.00 GiB total capacity; 137.92 GiB already allocated)"
    )
    print("Traceback (most recent call last):")
    print('  File "worker.py", line 214, in execute_model')
    print("    hidden_states = self.model(input_ids, positions, kv_caches)")
    print("torch.cuda.OutOfMemoryError: CUDA out of memory.")


def nccl_timeout_line(gpu_idx):
    print(
        f"{ts()} ERROR vllm[node={NODE_INDEX} gpu={gpu_idx}] "
        f"NCCL WARN Timeout waiting for collective operation to complete, "
        f"rank {gpu_idx}, op AllReduce, timeout_ms=600000"
    )


def xid_error_line(gpu_idx):
    xid_codes = [48, 63, 64, 79]  # real XID codes for common GPU faults
    code = random.choice(xid_codes)
    print(
        f"{ts()} ERROR kernel[node={NODE_INDEX}] "
        f"NVRM: Xid (PCI:0000:{gpu_idx:02x}:00): {code}, pid=<none>, name=<none>"
    )
    gpu_state[gpu_idx]["xid_errors"] += 1
    if code in (48, 63):
        gpu_state[gpu_idx]["ecc_errors"] += 1


def ts():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def main():
    threading.Thread(target=serve_metrics, daemon=True).start()
    threading.Thread(target=drift_metrics, daemon=True).start()

    print(f"{ts()} INFO fake-node-generator started node_index={NODE_INDEX} gpu_count={GPU_COUNT}")

    while True:
        for gpu_idx in range(GPU_COUNT):
            roll = random.random()
            if roll < FAULT_RATE / 3:
                cuda_oom_line(gpu_idx)
            elif roll < FAULT_RATE * 2 / 3:
                nccl_timeout_line(gpu_idx)
            elif roll < FAULT_RATE:
                xid_error_line(gpu_idx)
            else:
                normal_log_line(gpu_idx)
        sys.stdout.flush()
        time.sleep(LOG_INTERVAL_SECONDS)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except Exception:
        traceback.print_exc()
        sys.exit(1)
