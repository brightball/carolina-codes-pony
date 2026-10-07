# carolina-codes-pony

Read-only v1 polyglot API in **Pony** with **Stallion**. This repository is its own git remote. Treat it as the workspace root. The Phoenix CMS is a different remote (`github.com/brightball/carolina-codes`). Do not assume a sibling checkout exists, and do not fold this tree into the CMS remote.

The HTTP contract is the CMS file `priv/api/openapi.yaml` (with `priv/api/AGENTS.md`). This repo does not contain that OpenAPI file, `db/`, or `src/`. The live catalog is the CMS database (Postgres 16). Handler tests use a fake catalog and do not need Postgres.

Before changing listen, dial, the scheduler cap, the compiler pin, catalog failure, or Fly suspend, consult the decision ledger in [DECISIONS.md](DECISIONS.md) and the memory note in [MEMORY.md](MEMORY.md).

## Contract

Query PostgreSQL `v1_*` views: `v1_speakers`, `v1_sponsors`, `v1_years`, `v1_talks`, `v1_sponsorships`, `v1_year_speakers`, `v1_year_sponsors`. Never query Ash resource tables. Do not use base tables (`speakers`, `organizations`, `talks`) as the public contract.

List payloads are `{ "data": [ ... ] }`. Year-scoped speaker rows include `languages` and `topics` from `v1_talks`. Year-scoped sponsor rows include `tier`. Unknown slugs are 404. No writes. Ordinary JSON, not Ash JSON:API.

Routes:

- `GET /health` — `{"status":"ok"}`. Does not open a database connection.
- `GET /`
- `GET /v1/years`
- `GET /v1/speakers` and `GET /v1/speakers?year=`
- `GET /v1/speakers/{slug}` and `GET /v1/speakers/{year}/{slug}`
- `GET /v1/sponsors` and `GET /v1/sponsors?year=`
- `GET /v1/sponsors/{slug}` and `GET /v1/sponsors/{year}/{slug}`

Register once on boot: `POST {CAROLINA_URL}/internal/api-endpoints/register` with `Authorization: Bearer {POLYGLOT_REGISTER_TOKEN}`. No heartbeat. Registration is a no-op when `CAROLINA_URL` or `POLYGLOT_REGISTER_TOKEN` is empty. If the POST fails, log and keep serving.

| Variable | Example | Role |
| --- | --- | --- |
| `DATABASE_URL` | `postgres://postgres:postgres@127.0.0.1:5432/carolina_dev` | SQL views |
| `CAROLINA_URL` | `http://127.0.0.1:4000` | CMS (optional) |
| `POLYGLOT_REGISTER_TOKEN` | `dev` | Register bearer |
| `PUBLIC_BASE_URL` | `http://127.0.0.1:4023` | URL the CMS will call |
| `PORT` | `4023` | Listen port (the Fly process uses `8080`) |

## Pony + Stallion

Versions and package pins are in [README.md](README.md). ponyc ≥ 0.70.0, the identity string `0.70.1`, and the image tag `0.71.0` are three different facts.

- Lori cannot clear `IPV6_V6ONLY` before bind. The listener binds the IPv6 unspecified address with mapped IPv4 accepted. The sockaddr is a byte array: a Pony `struct` local is boxed, so `addressof` is not the C layout.
- Fly private names (`*.internal`, `*.flycast`, `*.fly.io`) are IPv6. `*.fly.dev` is a public name. A failed catalog connection, including a failed address lookup, is an error, not an empty row set.
- The production scheduler stays capped at one thread. Do not start one scheduler thread per host core.
- Each Stallion connection actor owns its own libpq connection. `Handler.apply` is the primitive PonyTest calls.
- Stallion's ssl dependency needs `-Dopenssl_3.0.x`. Leave the image on ponyc `0.71.0`.

## Commands

`ponyc` is not on the default PATH. The Makefile prepends ponyup (`~/.local/share/ponyup/bin`).

```bash
make test        # PonyTest, then test/test_ci_env.py
make sast        # Semgrep
make audit       # osv-scanner on the corral lock
make gitleaks
make lint        # pony-lint
make check       # local convenience; Gitea runs each gate as its own job
make hooks       # install pre-commit
```

Quality gates are `make test`, `make sast`, `make audit`, `make gitleaks`, and `make lint`.

## Where rulings go

Commands, conventions, and traps stay in this file. A restatement of the current handler does not. Dated choices go in the decision ledger, [DECISIONS.md](DECISIONS.md): append a new entry to supersede one. [MEMORY.md](MEMORY.md) lists what not to re-investigate and points at that ledger.
