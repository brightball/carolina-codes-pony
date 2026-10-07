# Agent memory

Pony + Stallion notes for the next session. This file is the short memory. The rulings are the append-only ledger in [DECISIONS.md](DECISIONS.md). Commands and traps that must be visible on every task are in [AGENTS.md](AGENTS.md). Version numbers are in [README.md](README.md).

Do not re-investigate these. Read the ledger entry instead of re-deriving it:

- HTTP stack, libpq versus `ponylang/postgres`, and one `PqCatalog` per connection actor: D1, D2.
- `-Dopenssl_3.0.x` and the image compiler pin (`0.71.0`, not `0.72.0`): D3, D4.
- The three Pony versions are different. Do not collapse ponyc ≥ 0.70.0, the identity string `0.70.1`, and the image tag `0.71.0`.
- A dead catalog connection or a failed Fly address lookup is an error, not an empty row set. `/health` opens no connection: D5.
- Fly suspend settings and the one-thread scheduler cap: D6. Do not raise `ponymaxthreads` or change VM size.
- IPv6 listen and Fly private dial (`*.internal`, `*.flycast`, `*.fly.io` only): D7.

When a ruling changes, add a new `DECISIONS.md` entry that names the one it supersedes. Then adjust the single line above. Do not copy the ledger into this file.
