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
make test
```

Requires `ponyc` ≥ 0.70.0, `corral`, OpenSSL 3 (`-Dopenssl_3.0.x`), and libpq. See [ASSESSMENT.md](ASSESSMENT.md) for the compile/run experience.
