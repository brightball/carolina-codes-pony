# Building the Carolina polyglot API with Pony and Stallion

Assessment of implementing the v1 speaker/sponsor contract in [Pony](https://www.ponylang.io/) with [Stallion](https://github.com/ponylang/stallion) as the HTTP stack, as of 2026-09-05.

**Verdict: fleet-ready.** `ponyc` 0.70.1 produced a native binary. `GET /health` is `{"status":"ok"}` without Postgres. Year-scoped speaker lists include `languages`/`topics` from `v1_talks`. The process registered with Elixir (`HTTP/1.1 200 OK`) and is wired into `ALL_APIS` on port **4023**.

## Toolchain on this machine

Pony was not on PATH. Official install is [ponyup](https://github.com/ponylang/ponyup):

```bash
sh -c "$(curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/ponylang/ponyup/latest-release/ponyup-init.sh)"
```

This host is Arch-based (`ID_LIKE=arch`, glibc 2.44). ponyup-init could not guess a distro triple (`lsb_release` missing; not Ubuntu/Alpine). Manual platform:

```bash
ponyup default x86_64-linux-ubuntu26.04
ponyup update ponyc release
ponyup update corral release
```

That installed **ponyc 0.70.1** (LLVM 22.1.6) and **corral 0.9.2** under `~/.local/share/ponyup`. The ubuntu26.04 glibc binary ran on Arch.

Stallion **0.11.0** requires ponyc ≥ 0.70.0. `corral add github.com/ponylang/stallion.git --version 0.11.0` pulled lori 0.20.0, uri 0.4.0, ssl 5.0.0, logger 1.0.1.

OpenSSL 3.6.3 and libpq were already present. Stallion’s ssl transitive dep **does not compile** until you pass a backend define:

```bash
corral run -- ponyc --path=. -Dopenssl_3.0.x -o build/carolina-codes-pony .
```

Without `-Dopenssl_3.0.x` the compiler stops at `ssl/net/_ssl_init.pony`: “You must select an SSL version to use.” That is the first real foot-gun after ponyc is installed.

## Language rules that actually mattered

The [reference-capability tutorial](https://tutorial.ponylang.io/reference-capabilities/reference-capabilities.html) is not optional documentation. Deny-capabilities showed up in this API in four places:

1. **`Catalog` is `ref`, on purpose.** libpq’s `PGconn` is not thread-safe and is not sendable. Each Stallion connection actor constructs its own `PqCatalog`. `Handler.apply` takes that `ref` and never stores it. Tests use `FakeCatalog` in the same actor. Sharing a `ref` catalog across actors would not compile — that is the feature.

2. **PonyTest `apply` is `box`.** `let cat = FakeCatalog` produced `FakeCatalog iso` (constructor in a box function). The tutorial’s `class iso _Test… is UnitTest` pattern still holds; creating a mutable catalog required `recover ref FakeCatalog end`, which is the documented way to get a local `ref` inside a `box` method.

3. **`String.substring` / `+` / `.string()` return `String iso^`.** Assigning those to an unannotated `let` infers `iso`, which then will not pass as `String val`. Annotate `let s: String val = …` or consume through a tiny `AsVal` primitive. This is the most frequent compile error for anyone coming from GC languages.

4. **FFI C strings vs `String.copy_cstring`.** `copy_cstring` wants `Pointer[U8] box` (it must read). A default `@PQgetvalue[Pointer[U8]]` is `tag` and cannot be read. Declaring the FFI return as `Pointer[U8] box` is the correct capability lie for “C owns this buffer, we copy immediately.” Copying *inside* `recover val` fails because `box` is not sendable; copy in a primitive, then `.clone()` to `val`.

Sendable values used everywhere else: identity JSON is `JSONObject val`, request paths are `String val`, Stallion’s `Request` is `class val`. That part of the type system felt natural once the catalog `ref` boundary was drawn.

Actors: `Main` registers once then starts `Listener` (`lori.TCPListenerActor`). `PolyglotServer` implements `stallion.HTTPServerActor` and calls `Handler.apply` in `on_request_complete`. `Registrar` is a one-shot lori client. No hidden notify objects — Stallion’s “your actor IS the connection” model matches the tutorial’s actor-per-connection advice.

## Stallion vs archived `http_server`

`ponylang/http_server` is archived (2026-05-30) and tells you to use Stallion. The hello example is the whole server shape: listener `_on_accept` → connection actor with `HTTPServer` + `ResponseBuilder`. Query parameters come from `request.uri.query_params()` (`uri.FormURLEncoded`). Default `TCPListener` ip version is `DualStack`; binding host `"::"` listened and still answered `127.0.0.1`.

Hobby-on-Stallion was not used. It would have added route sugar on top of the same listener; the contract is small enough that Stallion callbacks plus `Handler.apply` are clearer, and tests would still need the primitive handler.

`ponylang/postgres` is a pure-Pony actor client (callback/`Session`). That would have forced `long_test` for every catalog assertion. libpq FFI keeps Handler synchronous so PonyTest completes when `apply` returns — the [PonyTest long-test section](https://tutorial.ponylang.io/testing/ponytest.html) says to use `long_test` only when actors are required.

## Tests (community pattern)

`test/main.pony` follows the tutorial/`stdlib` layout:

- `actor Main is TestList` with `create(env)` and `make()`
- `class iso _Test… is UnitTest`
- hierarchical `name()` strings (`carolina/handler/speakers/year-scoped-languages-topics`)
- assertions against **`carolina.Handler`**, not a reimplementation
- no `long_test` (no actors under test)

12 tests ran, 12 passed (`build/pony-test/test`). They cover `/health` JSON (`status`/`ok`) with `sql_count == 0`, identity Pony/Stallion, 404 unknown slug, year-scoped `languages`/`topics`, year-scoped `tier`, and that year-scoped speaker SQL contains `v1_talks` and not `v1_year_speakers`.

## What compiled and ran

| Step | Result |
|------|--------|
| ponyup + ponyc 0.70.1 + corral 0.9.2 | ok (ubuntu26.04 triple on Arch) |
| `corral fetch` Stallion 0.11.0 | ok |
| PonyTest binary | ok with `-Dopenssl_3.0.x` |
| 12 PonyTest cases | passed |
| server binary `build/carolina-codes-pony/pony` | ok |
| `GET /health` | `{"status":"ok"}`, no Postgres |
| `GET /` | `language=Pony`, `framework=Stallion` |
| `GET /v1/speakers?year=2026` | `{data: …}` 27 real rows, languages/topics from `v1_talks` |
| Elixir register | `HTTP/1.1 200 OK` |
| Second launch | same |

There is no stand-in HTTP server in another language in this tree.

## Honest friction

- Arch is not a ponyup first-class distro; you pick a glibc Ubuntu triple by hand.
- Stallion pulls ssl even for plaintext HTTP; you will hit the SSL define before you hit your own code.
- `iso^` strings from `+` / `substring` / `.string()` dominate compile-error volume until you annotate `String val`.
- libpq FFI is more capability-work than `ponylang/postgres` would have been, but it keeps tests on the shipped handler without `long_test`.
- JSON object key order from `JSONPrinter` is not insertion order; tests parse with `JSONNav` instead of matching raw key sequence.

Pony did not “fight the HTTP API” once Handler was a primitive and Catalog stayed `ref` per actor. The difficulty the conference talk pointed at is real: it is almost entirely reference capabilities and FFI pointer caps, not Stallion’s request callback shape.
