# Decision ledger

Append-only record of durable choices for this Pony + Stallion API.

Ponylang's `AGENTS.md` guidance keeps commands, conventions, and traps in [AGENTS.md](AGENTS.md), because that file is read on every task and must not restate the current handler. This ledger is where the ruling lives: status, date, alternatives, why, and what would overturn it. Supersede a choice by adding a new entry that names the one it replaces. Do not rewrite an accepted entry. [MEMORY.md](MEMORY.md) points here; it does not copy these rulings. Current version numbers live in [README.md](README.md).

## D1 — HTTP stack is Stallion

- Status: accepted
- Date: 2026-09-05
- Alternatives: `ponylang/http_server` (archived 2026-05-30); Hobby on top of Stallion.
- Why: Stallion is the maintained HTTP server. The contract is small enough that Stallion callbacks plus `Handler.apply` stay testable without a routing framework. Each connection is an actor, which matches one libpq connection per request (see D2).
- Overturn: Stallion is unmaintained and a replacement can keep `Handler.apply` synchronous for PonyTest.

## D2 — Catalog client is libpq, one connection per actor

- Status: accepted
- Date: 2026-09-05
- Alternatives: `ponylang/postgres`, a pure-Pony actor client with callback sessions.
- Why: `PGconn` is not sendable. Each Stallion connection actor owns its own `PqCatalog ref`, so the pointer never crosses an actor boundary. `Handler.apply` stays a primitive. PonyTest calls that function and finishes when it returns, without `long_test`.
- Overturn: libpq FFI cannot be kept safe, and catalog tests can still call the shipped handler synchronously.

## D3 — OpenSSL 3 compile define

- Status: accepted
- Date: 2026-09-05
- Alternatives: compile Stallion's ssl dependency with no backend define.
- Why: Stallion pulls `ponylang/ssl` even for plaintext HTTP. ssl 5.0.0 does not compile until the backend is selected. This tree passes `-Dopenssl_3.0.x` in the Makefile and the image build.
- Overturn: the pinned ssl package no longer requires a backend define, or the HTTP stack no longer depends on it.

## D4 — Image compiler stays on ponyc 0.71.0

- Status: accepted
- Date: 2026-09-15
- Alternatives: `ghcr.io/ponylang/ponyc:0.72.0`; treating the local identity string `0.70.1` as the image tag.
- Why: The `Dockerfile` records that ponyc 0.72.0 replaced stdlib `net` with Lori, and Stallion 0.11.0 plus ssl 5.0.0 clash on SSL types. The image is `ghcr.io/ponylang/ponyc:0.71.0` on Alpine (musl). `Identity.language_version()` remains the string `0.70.1` from the machine that first built this sibling. Those are different compilers. Stallion 0.11.0 only requires ponyc ≥ 0.70.0.
- Overturn: Stallion and ssl publish a release that compiles on ponyc 0.72 or later. Changing the identity JSON is a contract change and is not part of moving the image tag.

## D5 — A failed catalog connection is an error

- Status: accepted
- Date: 2026-09-22
- Alternatives: return an empty row set when libpq cannot connect, when the connection dies, or when a Fly address lookup fails.
- Why: An empty array is a successful query with zero rows (unknown slug, no matches). `PqDrop` finishes a dead connection. A Fly host with no resolved address fails the query the same way. `GET /health` does not open a connection and does not run SQL.
- Overturn: the v1 contract defines a failed catalog connection as an empty list.

## D6 — Suspend idle Fly machines; one scheduler thread

- Status: accepted
- Date: 2026-09-22
- Alternatives: leave the machine running; let the Pony runtime start one scheduler thread per host core; raise `ponyminthreads`.
- Why: `fly.toml` keeps `auto_stop_machines = "suspend"`, `auto_start_machines = true`, `min_machines_running = 0`, `memory = "256mb"`, `cpu_kind = "shared"`, `cpus = 1`, and a `GET /health` check. The runtime would otherwise start one scheduler thread per host core before `Main`. `SchedCap.threads()` is 1, applied with `@runtime_override_defaults` as `ponymaxthreads`. Idle `/health` and `/` still answer in under a second with that cap, so `ponyminthreads` stays at its default.
- Overturn: the production VM is larger than one shared CPU and cold start no longer matters, or suspend itself fails the health check. Do not change VM size or leave `suspend` as a side effect of unrelated work.

## D7 — Listen on IPv6 any; dial Fly private names over IPv6

- Status: accepted
- Date: 2026-09-30
- Alternatives: Lori `TCPListener` (it cannot set `IPV6_V6ONLY` before bind); `AF_UNSPEC` `getaddrinfo` for Fly private DNS; treating `*.fly.dev` as a private name.
- Why: Fly's proxy and 6PN are IPv6. Lori calls `getaddrinfo` and never clears `IPV6_V6ONLY`. The process binds the IPv6 unspecified address with `IPV6_V6ONLY` off so mapped IPv4 clients are accepted. A Pony `struct` local is boxed, so the sockaddr is an explicit byte array. Fly private DNS (`*.internal`, `*.flycast`, `*.fly.io`) is AAAA-only; an A lookup is NXDOMAIN, and musl treats that as a missing name. Those hosts are dialed as IPv6 (`hostaddr` for libpq, Lori `IP6` for registration). `*.fly.dev` is a public name and is not forced to IPv6. Registration still no-ops when `CAROLINA_URL` or `POLYGLOT_REGISTER_TOKEN` is empty, and the listener is armed before that dial.
- Overturn: Lori can set `IPV6_V6ONLY` before bind, and musl `getaddrinfo` of an AAAA-only name succeeds for `AF_UNSPEC`.
