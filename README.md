# carolina-codes-pony

Read-only v1 polyglot API for Carolina Code Conference. **Pony** + **Stallion** (not the archived `http_server` package, not the raw `php/` sibling).

Catalog SQL uses libpq against PostgreSQL `v1_*` views. Each Stallion connection actor owns its own `PqCatalog ref` so the `PGconn` never crosses an actor boundary. `Handler.apply` is a primitive; PonyTest drives that same function.

```bash
DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/carolina_dev \
CAROLINA_URL=http://127.0.0.1:4000 \
POLYGLOT_REGISTER_TOKEN=dev \
PUBLIC_BASE_URL=http://127.0.0.1:4023 \
PORT=4023 \
./bin/server
```

`GET /` reports `language: "Pony"` and `framework: "Stallion"`. `GET /health` returns `{"status":"ok"}` without touching Postgres.

```bash
make test        # PonyTest (fake catalog, no Postgres)
make sast        # Semgrep p/security-audit + .semgrep.yml
make audit       # osv-scanner against corral lock.json GitHub commits
make gitleaks    # secret scan of this git tree
make lint        # pony-lint on carolina/, test/, main.pony
make check       # all of the above (local convenience only)
make hooks       # install local pre-commit hooks
```

Pre-commit runs the same five checks (`local tests`, `static security scanner`, `3rd-party dependency scanner`, `gitleaks`, `pony-lint`). Install once with `make hooks` (needs `pre-commit` on PATH). Emergency skip: `SKIP=local-tests,sast,audit,gitleaks,pony-lint git commit`.

Requires `ponyc` ≥ 0.70.0, `corral`, OpenSSL 3 (`-Dopenssl_3.0.x`), and libpq. `pony-lint` ships with ponyc. See [ASSESSMENT.md](ASSESSMENT.md) for the compile/run experience.
