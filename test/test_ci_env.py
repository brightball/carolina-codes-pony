#!/usr/bin/env python3
"""Drive the shipped scripts/ci-env.sh pack/unpack and artifact round-trip."""

from __future__ import annotations

import base64
import hashlib
import json
import os
import shutil
import stat
import subprocess
import tempfile
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "ci-env.sh"
PONYC_IMAGE = "ghcr.io/ponylang/ponyc:0.71.0"
OVERLAY_PYTHON = "usr/bin/python3"
OVERLAY_SSL = "usr/include/openssl/ssl.h"
OVERLAY_LIBPQ = "usr/include/postgresql/libpq-fe.h"


def _md5_name(name: str) -> str:
    return hashlib.md5(name.encode(), usedforsecurity=False).hexdigest()


class _FakeGitea(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):
        return

    def _check_auth(self) -> bool:
        got = self.headers.get("Authorization") or ""
        if not got.startswith("Bearer "):
            self.send_error(401, "Bad authorization header")
            return False
        return True

    def _read_body(self) -> bytes:
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def _json(self, payload: dict) -> None:
        blob = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(blob)))
        self.end_headers()
        self.wfile.write(blob)

    def _public_url(self, path: str) -> str:
        return f"http://{self.headers.get('Host')}{path}"

    def _parse(self):
        parsed = urllib.parse.urlparse(self.path)
        parts = parsed.path.split("/")
        query = urllib.parse.parse_qs(parsed.query)
        return parts, query

    def do_POST(self):
        if not self._check_auth():
            return
        req = json.loads(self._read_body() or b"{}")
        name = req.get("Name") or req.get("name")
        if not name:
            self.send_error(400, "missing Name")
            return
        artifact_hash = _md5_name(name)
        self.server.pending[name] = {}
        self._json(
            {
                "fileContainerResourceUrl": self._public_url(
                    f"/api/actions_pipeline/_apis/pipelines/workflows/{self.server.run_id}/artifacts/{artifact_hash}/upload"
                )
            }
        )

    def do_PUT(self):
        if not self._check_auth():
            return
        _parts, query = self._parse()
        item_path = (query.get("itemPath") or [""])[0]
        body = self._read_body()
        digest = hashlib.md5(body, usedforsecurity=False).digest()
        want = base64.b64encode(digest).decode("ascii")
        if (self.headers.get("x-actions-results-md5") or "") != want:
            self.send_error(500, "md5 not match")
            return
        self.server.pending[item_path] = body
        self._json({"message": "success"})

    def do_PATCH(self):
        if not self._check_auth():
            return
        _parts, query = self._parse()
        name = (query.get("artifactName") or [""])[0]
        for item_path, body in list(self.server.pending.items()):
            if not item_path.startswith(name + "/"):
                continue
            art_id = str(self.server.next_id)
            self.server.next_id += 1
            self.server.confirmed[art_id] = {
                "id": art_id,
                "name": name,
                "path": item_path[len(name) + 1 :],
                "contents": body,
            }
            del self.server.pending[item_path]
        self._json({"message": "success"})

    def do_GET(self):
        if not self._check_auth():
            return
        parts, query = self._parse()
        path = urllib.parse.urlparse(self.path).path
        if path.endswith("/artifacts") or path.rstrip("/").endswith("/artifacts"):
            seen = set()
            items = []
            for art in self.server.confirmed.values():
                if art["name"] in seen:
                    continue
                seen.add(art["name"])
                items.append(
                    {
                        "name": art["name"],
                        "fileContainerResourceUrl": self._public_url(
                            f"/api/actions_pipeline/_apis/pipelines/workflows/{self.server.run_id}/artifacts/{_md5_name(art['name'])}/download_url"
                        ),
                    }
                )
            if not items:
                self.send_error(404)
                return
            self._json({"count": len(items), "value": items})
            return
        if path.endswith("/download_url"):
            name = (query.get("itemPath") or [""])[0]
            files = []
            for art in self.server.confirmed.values():
                if art["name"] != name:
                    continue
                files.append(
                    {
                        "path": f"{art['name']}/{art['path']}",
                        "itemType": "file",
                        "contentLocation": self._public_url(
                            f"/api/actions_pipeline/_apis/pipelines/workflows/{self.server.run_id}/artifacts/{art['id']}/download"
                        ),
                    }
                )
            if not files:
                self.send_error(404)
                return
            self._json({"value": files})
            return
        if "/download" in path:
            art_id = None
            for i, part in enumerate(parts):
                if part == "artifacts" and i + 1 < len(parts):
                    art_id = parts[i + 1]
                    break
            art = self.server.confirmed.get(art_id or "")
            if art is None:
                self.send_error(404)
                return
            blob = art["contents"]
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(blob)))
            self.end_headers()
            self.wfile.write(blob)
            return
        self.send_error(404)


def _start_fake_gitea():
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), _FakeGitea)
    httpd.run_id = "791"
    httpd.next_id = 1
    httpd.pending = {}
    httpd.confirmed = {}
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    return httpd


def _run_ci_env(cmd: str, env: dict[str, str]) -> str:
    merged = os.environ.copy()
    merged.update(env)
    result = subprocess.run(
        ["sh", str(SCRIPT), cmd],
        cwd=str(ROOT),
        env=merged,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise AssertionError(
            f"ci-env.sh {cmd} failed ({result.returncode})\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result.stdout + result.stderr


class CiEnvHelperTests(unittest.TestCase):
    def test_pack_unpack_preserves_project_files_and_executable_tools(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ws = root / "ws"
            tools = root / "tools"
            overlay = root / "overlay"
            ws.mkdir()
            (tools / "bin").mkdir(parents=True)
            overlay.mkdir()
            (ws / "Makefile").write_text("test:\n\ttrue\n")
            (ws / "carolina.pony").write_text('actor Main\n  new create(env: Env) => None\n')
            semgrep = tools / "bin" / "semgrep"
            semgrep.write_text("#!/bin/sh\necho semgrep\n")
            semgrep.chmod(0o755)
            tar_path = root / "prepared-env.tar.gz"
            env = {
                "GITHUB_WORKSPACE": str(ws),
                "CI_ENV_TOOLS_DIR": str(tools),
                "CI_ENV_OVERLAY_DIR": str(overlay),
                "CI_ENV_TAR": str(tar_path),
                "CI_ENV_ARTIFACT_NAME": "prepared-env",
            }
            _run_ci_env("pack", env)
            self.assertTrue(tar_path.is_file(), "pack did not write tarball")

            ws2 = root / "ws2"
            tools2 = root / "tools2"
            overlay2 = root / "overlay2"
            restore_env = {
                "GITHUB_WORKSPACE": str(ws2),
                "CI_ENV_TOOLS_DIR": str(tools2),
                "CI_ENV_OVERLAY_DIR": str(overlay2),
                "CI_ENV_TAR": str(tar_path),
                "CI_ENV_ARTIFACT_NAME": "prepared-env",
            }
            _run_ci_env("unpack", restore_env)

            self.assertEqual((ws2 / "Makefile").read_text(), "test:\n\ttrue\n")
            self.assertEqual(
                (ws2 / "carolina.pony").read_text(),
                'actor Main\n  new create(env: Env) => None\n',
            )
            restored = tools2 / "bin" / "semgrep"
            self.assertEqual(restored.read_text(), "#!/bin/sh\necho semgrep\n")
            mode = restored.stat().st_mode
            self.assertTrue(
                mode & stat.S_IXUSR,
                f"restored semgrep is not executable: {stat.filemode(mode)}",
            )

    def test_prepare_restore_round_trip_via_mock_artifact_api(self):
        httpd = _start_fake_gitea()
        try:
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                ws = root / "ws"
                tools = root / "tools"
                overlay = root / "overlay"
                ws.mkdir()
                (tools / "bin").mkdir(parents=True)
                overlay.mkdir()
                (ws / "README.md").write_text("carolina-codes-pony\n")
                gitleaks = tools / "bin" / "gitleaks"
                gitleaks.write_text("gitleaks-bin\n")
                gitleaks.chmod(0o755)
                (overlay / "usr-bin-make").write_text("make-stub\n")
                host = f"http://127.0.0.1:{httpd.server_address[1]}"
                tar_path = root / "prepared-env.tar.gz"
                common = {
                    "ACTIONS_RUNTIME_URL": host + "/api/actions_pipeline/",
                    "ACTIONS_RUNTIME_TOKEN": "test-token",
                    "GITHUB_RUN_ID": "791",
                    "GITHUB_SERVER_URL": host,
                    "CI_ENV_SKIP_INSTALL": "1",
                    "CI_ENV_ARTIFACT_NAME": "prepared-env",
                }
                _run_ci_env(
                    "prepare",
                    {
                        **common,
                        "GITHUB_WORKSPACE": str(ws),
                        "CI_ENV_TOOLS_DIR": str(tools),
                        "CI_ENV_OVERLAY_DIR": str(overlay),
                        "CI_ENV_TAR": str(tar_path),
                    },
                )
                ws2 = root / "restored"
                tools2 = root / "tools-restored"
                overlay2 = root / "overlay-restored"
                tar2 = root / "downloaded.tar.gz"
                _run_ci_env(
                    "restore",
                    {
                        **common,
                        "GITHUB_WORKSPACE": str(ws2),
                        "CI_ENV_TOOLS_DIR": str(tools2),
                        "CI_ENV_OVERLAY_DIR": str(overlay2),
                        "CI_ENV_TAR": str(tar2),
                    },
                )
                self.assertEqual((ws2 / "README.md").read_text(), "carolina-codes-pony\n")
                restored = tools2 / "bin" / "gitleaks"
                self.assertEqual(restored.read_text(), "gitleaks-bin\n")
                self.assertTrue(restored.stat().st_mode & stat.S_IXUSR)
                self.assertEqual((overlay2 / "usr-bin-make").read_text(), "make-stub\n")
        finally:
            httpd.shutdown()
            httpd.server_close()

    def test_ponyc_overlay_restore_provides_python_and_headers(self):
        """Drive shipped overlay+pack+unpack on ponyc:0.71.0 (apk-tools 3).

        apk add --no-cache drops the index, so apk fetch cannot populate
        the overlay. Check jobs only get python3/openssl-dev/libpq-dev if
        write_apk_overlay snapshots installed files.
        """
        if shutil.which("docker"):
            self._assert_overlay_roundtrip_in_ponyc_image()
            return
        restored = Path("/opt/ci-tools")
        if restored.is_dir():
            for rel in (OVERLAY_PYTHON, OVERLAY_SSL, OVERLAY_LIBPQ):
                path = Path("/") / rel
                self.assertTrue(
                    path.exists(),
                    f"restored check-job environment missing {path}",
                )
            return
        self.fail(
            "docker is required to verify scripts/ci-env.sh overlay on "
            f"{PONYC_IMAGE} (apk fetch is empty after apk add --no-cache)"
        )

    def _assert_overlay_roundtrip_in_ponyc_image(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            (work / "ws").mkdir()
            (work / "ws" / "README.md").write_text("overlay-fixture\n")
            script_mount = work / "ci-env.sh"
            shutil.copy(SCRIPT, script_mount)
            inner = r"""
set -euo pipefail
export GITHUB_WORKSPACE=/work/ws
export CI_ENV_TAR=/work/prepared-env.tar.gz
export CI_ENV_TOOLS_DIR=/opt/ci-tools
export CI_ENV_OVERLAY_DIR=/opt/ci-overlay
sh /work/ci-env.sh overlay
mkdir -p /opt/ci-tools/bin
printf '#!/bin/sh\necho semgrep\n' > /opt/ci-tools/bin/semgrep
chmod +x /opt/ci-tools/bin/semgrep
test -e /opt/ci-overlay/usr/bin/python3
test -e /opt/ci-overlay/usr/include/openssl/ssl.h
test -e /opt/ci-overlay/usr/include/postgresql/libpq-fe.h
sh /work/ci-env.sh pack
"""
            prepare = subprocess.run(
                [
                    "docker",
                    "run",
                    "--rm",
                    "--user",
                    "root",
                    "-v",
                    f"{work}:/work",
                    PONYC_IMAGE,
                    "sh",
                    "-c",
                    inner,
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            if prepare.returncode != 0:
                raise AssertionError(
                    "ci-env.sh overlay/pack in ponyc image failed "
                    f"({prepare.returncode})\nstdout:\n{prepare.stdout}\n"
                    f"stderr:\n{prepare.stderr}"
                )
            tar_path = work / "prepared-env.tar.gz"
            self.assertTrue(tar_path.is_file(), "pack did not write tarball")

            restore = r"""
set -euo pipefail
export GITHUB_WORKSPACE=/restored
export CI_ENV_TAR=/work/prepared-env.tar.gz
export CI_ENV_TOOLS_DIR=/opt/ci-tools
export CI_ENV_OVERLAY_DIR=/opt/ci-overlay
mkdir -p /restored
sh /work/ci-env.sh unpack
test -e /usr/bin/python3
test -f /usr/include/openssl/ssl.h
test -f /usr/include/postgresql/libpq-fe.h
python3 -c 'import sys; print(sys.version)'
test -x /opt/ci-tools/bin/semgrep
test -f /restored/README.md
grep -q overlay-fixture /restored/README.md
"""
            check = subprocess.run(
                [
                    "docker",
                    "run",
                    "--rm",
                    "--user",
                    "root",
                    "-v",
                    f"{work}:/work",
                    PONYC_IMAGE,
                    "sh",
                    "-c",
                    restore,
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            if check.returncode != 0:
                raise AssertionError(
                    "fresh ponyc check-job unpack missing python/headers "
                    f"({check.returncode})\nstdout:\n{check.stdout}\n"
                    f"stderr:\n{check.stderr}"
                )
            self.assertIn("3.", check.stdout)


if __name__ == "__main__":
    unittest.main()
