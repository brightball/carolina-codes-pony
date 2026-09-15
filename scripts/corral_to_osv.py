#!/usr/bin/env python3
"""Map corral lock.json GitHub locators to osv-scanner's custom lock format.

osv-scanner does not parse corral lock.json. This writes osv-scanner-custom.json
with git commits for Stallion and its transitives so the audit actually queries
OSV instead of walking an empty tree.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCK_PATH = os.path.join(ROOT, "lock.json")
OUT_PATH = os.path.join(ROOT, "osv-scanner-custom.json")


def _run(args: list[str], cwd: str | None = None) -> str:
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def _repo_dir(locator: str) -> str:
    slug = locator.replace("/", "_").replace(".", "_")
    return os.path.join(ROOT, "_repos", slug)


def _peel_ls_remote(text: str) -> str | None:
    peeled = None
    tagged = None
    for line in text.splitlines():
        if not line.strip():
            continue
        sha, ref = line.split(None, 1)
        if ref.endswith("^{}"):
            peeled = sha
        else:
            tagged = sha
    return peeled or tagged


def resolve_commit(locator: str, revision: str) -> str:
    local = _repo_dir(locator)
    if os.path.isdir(local):
        for spec in (f"{revision}^{{commit}}", revision, "HEAD"):
            try:
                return _run(["git", "-C", local, "rev-parse", spec])
            except subprocess.CalledProcessError:
                continue

    url = "https://" + locator
    refs = [f"refs/tags/{revision}", f"refs/tags/{revision}^{{}}"]
    try:
        listing = _run(["git", "ls-remote", url, *refs])
    except subprocess.CalledProcessError as exc:
        raise SystemExit(f"git ls-remote failed for {locator}@{revision}: {exc}") from exc
    sha = _peel_ls_remote(listing)
    if not sha:
        try:
            listing = _run(["git", "ls-remote", url, revision, f"{revision}^{{}}"])
            sha = _peel_ls_remote(listing)
        except subprocess.CalledProcessError:
            sha = None
    if not sha:
        raise SystemExit(f"could not resolve commit for {locator}@{revision}")
    return sha


def main() -> int:
    with open(LOCK_PATH, encoding="utf-8") as fh:
        lock = json.load(fh)

    packages = []
    print("scanning corral lock.json GitHub locators:")
    for entry in lock.get("locks", []):
        locator = entry.get("locator", "")
        revision = entry.get("revision", "")
        if not locator or locator == ".":
            continue
        if not locator.startswith("github.com/"):
            print(f"  skip non-github locator {locator}", file=sys.stderr)
            continue
        name = locator[:-4] if locator.endswith(".git") else locator
        commit = resolve_commit(locator, revision)
        print(f"  {name} @ {revision} -> {commit}")
        packages.append({"package": {"name": name, "commit": commit}})

    required = (
        "github.com/ponylang/stallion",
        "github.com/ponylang/lori",
        "github.com/ponylang/ssl",
        "github.com/ponylang/uri",
        "github.com/ponylang/logger",
    )
    names = {p["package"]["name"] for p in packages}
    missing = [n for n in required if n not in names]
    if missing:
        raise SystemExit(f"lock.json did not produce OSV packages for: {missing}")

    payload = {"results": [{"packages": packages}]}
    with open(OUT_PATH, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2)
        fh.write("\n")
    print(f"wrote {OUT_PATH} ({len(packages)} packages)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
