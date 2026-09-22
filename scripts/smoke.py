#!/usr/bin/env python3
"""Start the non-debug server and require /health and / within 3 seconds.

Postgres and the CMS are pointed at a closed port. The binary caps its own
scheduler threads; this script does not pass --ponymaxthreads.
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


def fetch_first(port: int, path: str, timeout: float) -> tuple[int, dict[str, str], str]:
    errors: list[str] = []
    for host in ("127.0.0.1", "::1"):
        try:
            return fetch(host, port, path, timeout)
        except OSError as exc:
            errors.append(f"{host}:{port}{path}: {exc}")
    raise OSError("; ".join(errors))


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
                health = fetch_first(port, "/health", 0.4)
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

        ident_status, ident_headers, ident_body = fetch_first(port, "/", 2.0)
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
