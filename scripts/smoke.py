#!/usr/bin/env python3
"""Start the non-debug server and require /health and / within 3 seconds.

Postgres and the CMS are pointed at a closed port. The binary caps its own
scheduler threads; this script does not pass --ponymaxthreads.

The listen socket must be the IPv6 unspecified address, and a 127.0.0.1
client must still receive /health. After the process has been idle for more
than one second, /health and / must answer again in under one second.
"""

from __future__ import annotations

import http.client
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path


def free_port() -> int:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    port = int(sock.getsockname()[1])
    sock.close()
    return port


def fetch(host: str, port: int, path: str, timeout: float) -> tuple[int, dict[str, str], str]:
    conn = http.client.HTTPConnection(host, port, timeout=timeout)
    try:
        conn.request("GET", path)
        response = conn.getresponse()
        body = response.read().decode("utf-8")
        headers = {key.lower(): value for key, value in response.getheaders()}
        return int(response.status), headers, body
    finally:
        conn.close()


def tcp6_listeners(pid: int, port: int) -> list[str]:
    """IPv6 local addresses (32 hex chars) this process is listening on."""
    hex_port = f"{port:04X}"
    inodes: set[str] = set()
    for entry in Path(f"/proc/{pid}/fd").iterdir():
        try:
            target = os.readlink(entry)
        except OSError:
            continue
        if target.startswith("socket:[") and target.endswith("]"):
            inodes.add(target[len("socket:[") : -1])
    found: list[str] = []
    lines = Path("/proc/net/tcp6").read_text(encoding="utf-8").splitlines()
    for line in lines[1:]:
        parts = line.split()
        if len(parts) < 10:
            continue
        local, inode = parts[1], parts[9]
        if inode not in inodes:
            continue
        addr, local_port = local.split(":")
        if local_port.upper() != hex_port:
            continue
        found.append(addr.upper())
    return found


def thread_count(pid: int) -> int:
    for line in Path(f"/proc/{pid}/status").read_text(encoding="utf-8").splitlines():
        if line.startswith("Threads:"):
            return int(line.split()[1])
    raise RuntimeError(f"/proc/{pid}/status has no Threads line")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: smoke.py <pony-binary>")
    binary = sys.argv[1]
    port = free_port()
    env = os.environ.copy()
    env["PORT"] = str(port)
    env["DATABASE_URL"] = "postgres://postgres:postgres@127.0.0.1:1/carolina_dev"
    env["CAROLINA_URL"] = ""
    env["POLYGLOT_REGISTER_TOKEN"] = ""
    env.pop("PONYMAXTHREADS", None)

    log_path = Path(binary).resolve().parent / "smoke-server.log"
    log_file = log_path.open("w", encoding="utf-8")
    started = time.monotonic()
    proc = subprocess.Popen(
        [binary],
        env=env,
        stdout=log_file,
        stderr=subprocess.STDOUT,
    )
    health: tuple[int, dict[str, str], str] | None = None
    try:
        deadline = started + 3.0
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                log_file.flush()
                raise SystemExit(
                    f"server exited {proc.returncode} before /health\n"
                    + log_path.read_text(encoding="utf-8")
                )
            try:
                health = fetch("127.0.0.1", port, "/health", 0.4)
                break
            except OSError:
                time.sleep(0.05)
        if health is None:
            raise SystemExit("GET /health did not return within 3 seconds of process start")
        elapsed = time.monotonic() - started
        status, headers, body = health
        print(f"health_status={status}")
        print(f"health_elapsed_s={elapsed:.3f}")
        print(f"health_body={body}")
        print("health_headers=" + " ".join(f"{k}:{v}" for k, v in headers.items()))
        if status != 200:
            raise SystemExit(f"/health status {status}")
        parsed = json.loads(body)
        if parsed.get("status") != "ok":
            raise SystemExit(f"/health JSON status is {parsed.get('status')!r}")

        listeners = tcp6_listeners(proc.pid, port)
        print("listen_tcp6=" + ",".join(listeners))
        unspecified = "00000000000000000000000000000000"
        loopback = "00000000000000000000000000000001"
        if unspecified not in listeners:
            raise SystemExit(
                f"listen socket is not IPv6 unspecified: {listeners}"
            )
        if listeners == [loopback]:
            raise SystemExit("listen socket is ::1 only")

        ident_status, ident_headers, ident_body = fetch("127.0.0.1", port, "/", 2.0)
        print(f"root_status={ident_status}")
        print(f"root_body={ident_body}")
        print("root_headers=" + " ".join(f"{k}:{v}" for k, v in ident_headers.items()))
        if ident_status != 200:
            raise SystemExit(f"/ status {ident_status}")
        ident = json.loads(ident_body)
        if ident.get("language") != "Pony" or ident.get("framework") != "Stallion":
            raise SystemExit(f"/ identity JSON is {ident_body}")
        if ident_headers.get("x-polyglot-language") != "Pony":
            raise SystemExit(f"missing X-Polyglot-Language in {ident_headers}")
        if ident_headers.get("x-polyglot-framework") != "Stallion":
            raise SystemExit(f"missing X-Polyglot-Framework in {ident_headers}")

        cores = os.cpu_count() or 1
        threads = thread_count(proc.pid)
        print(f"nproc={cores}")
        print(f"pid={proc.pid}")
        print(f"threads={threads}")
        # One scheduler plus a small fixed runtime overhead, not one thread per core.
        if cores > 1 and threads > 8:
            raise SystemExit(
                f"scheduler was not capped: threads={threads} nproc={cores}"
            )
        if elapsed >= 3.0:
            raise SystemExit(f"/health took {elapsed:.3f}s")

        time.sleep(1.1)
        idle_at = time.monotonic()
        idle_status, _, idle_body = fetch("127.0.0.1", port, "/health", 2.0)
        idle_elapsed = time.monotonic() - idle_at
        print(f"idle_health_status={idle_status}")
        print(f"idle_health_elapsed_s={idle_elapsed:.3f}")
        print(f"idle_health_body={idle_body}")
        if idle_status != 200:
            raise SystemExit(f"idle /health status {idle_status}")
        if json.loads(idle_body).get("status") != "ok":
            raise SystemExit(f"idle /health body is {idle_body}")
        if idle_elapsed >= 1.0:
            raise SystemExit(f"idle /health took {idle_elapsed:.3f}s")

        root_at = time.monotonic()
        root_status, _, root_body = fetch("127.0.0.1", port, "/", 2.0)
        root_elapsed = time.monotonic() - root_at
        print(f"idle_root_status={root_status}")
        print(f"idle_root_elapsed_s={root_elapsed:.3f}")
        print(f"idle_root_body={root_body}")
        if root_status != 200:
            raise SystemExit(f"idle / status {root_status}")
        root_ident = json.loads(root_body)
        if root_ident.get("language") != "Pony" or root_ident.get("framework") != "Stallion":
            raise SystemExit(f"idle / identity JSON is {root_body}")
        if root_elapsed >= 1.0:
            raise SystemExit(f"idle / took {root_elapsed:.3f}s")
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
        log_file.close()


if __name__ == "__main__":
    main()
