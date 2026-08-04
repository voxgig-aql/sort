# CLAUDE.md

This repository is the `Sort` sorting-algorithms library, written in boru.

## Using the library

See @AGENTS.md for how to call the `Sort` API correctly from boru — the
calling convention, the full API, copy-paste idioms, and the common
mistakes to avoid. Every example there is verified against the pinned
`boru` build.

## Working on this repository

- A SessionStart hook (`.claude/settings.json` →
  `.claude/hooks/session-start.sh`) builds `boru` from the pinned commit in
  remote sessions, so a fresh session can run the suites. Locally, build it
  once from source (there is no tagged release and `go install …/aql@latest`
  is blocked by replace directives) — see
  [docs/how-to.md](docs/how-to.md#install-and-run-aql).
- The whole library is one file, `sort.aql`, exporting the single `Sort`
  namespace: the comparators and the algorithms must share a module
  because boru resolves a comparator function's free words in the module
  that *runs* it (a comparator with a private helper would not resolve if
  the sort that invokes it lived elsewhere).
- Tests live in `test/`, named `sort_<unit|prop>_<test|spec>.aql` plus a
  `sort_smoke_test.aql`: `_test` = imperative (`Test.test`/
  `Test.check-prop`), `_spec` = declarative spec; `unit` = example-based,
  `prop` = property-based. Each assertion-bearing suite ends by asserting
  `Test.fail-count` is `0` and prints `all green`. The keystone property is
  **cross-agreement**: every algorithm must return the same ordering as the
  stable `Sort.merge`.
- `test/divergence/run.sh` runs every suite through all three boru surfaces
  — interpreter, `boru check`, and the byte compiler (`boru --compile`). The
  interpreter and byte compiler are **gating** (they must succeed and
  agree); `boru check` is **advisory** here, because its static analysis has
  known false positives on first-class function values, which this library
  threads through every sort. See its `README.md`.
- boru-runtime gotchas discovered while building this library are captured
  inline as code comments in `sort.aql` and in AGENTS.md's "Common
  mistakes". The pinned boru commit is single-sourced in the CI workflow's
  `BORU_REF` (`.github/workflows/test.yml`, currently boru `6185620`); a CI
  job fails if the hook or `api.json` drift from it.
- Forking this repo to start a new boru library? See `TEMPLATE.md`.
