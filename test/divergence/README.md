# Three-way test check: interpreter · check · byte compiler

This library's `.aql` suites are written once and must mean the same thing
no matter how `aql` runs them. `run.sh` runs every suite through all three
execution surfaces:

```bash
aql X            # interpreter — the default; what CI and users run   (GATING)
aql check X      # static type-check                                  (ADVISORY)
aql --compile X  # byte compiler — bytecode when compilable, else a SILENT
                 #   fallback to the interpreter; documented to be IDENTICAL
                 #   to it ("opt-in performance, never semantics")     (GATING)
```

It also prints an `aql --force-compile X` coverage line per suite — how much
of each program the bytecode emitter can fully lower today. Refusals there
are expected gaps (under `--compile` they fall back to the interpreter), not
failures.

## What gates, and why `check` is advisory

The **interpreter** and the **byte compiler** are gating: a non-zero
interpreter run, or any difference between `aql --compile X` and `aql X`,
fails the script. That interpreter == byte-compiler equality is the real
correctness guarantee.

`aql check` is **reported but not gating**. Its static analysis has known
false positives on first-class function values, and this library threads
comparator *functions* through every sort — passing them as parameters,
forwarding them through recursion, capturing them in closures — plus a
recursive `radix-msd`. The checker flags a handful of those call sites even
though the interpreter and the byte compiler both run them and agree. Gating
on `check` would block a library that is provably correct, so the harness
surfaces the count (`advisory(N)`) without failing. (The CI workflow likewise
runs `aql check --soft` on the library as advisory — see `ci/test.yml`.)

## Running it

```bash
test/divergence/run.sh
```

`run.sh` builds its own aql at a ref pinned in the script (the same `12a44e0`
the library pins; pinning it here keeps the harness self-contained, so it
never depends on whatever aql is on `PATH`), then prints a per-suite matrix:

```
  SUITE                         INTERPRETER   CHECK             BYTECODE
  sort_unit_test.aql            ok            ok                ok
  sort_unit_spec.aql            ok            ok                ok
  sort_prop_test.aql            ok            ok                ok
  sort_prop_spec.aql            ok            ok                ok
  sort_smoke_test.aql           ok            advisory(3)       ok
```

It exits non-zero on any interpreter failure or any difference between
`aql --compile X` and `aql X`; `check` columns are informational. Needs `go`
+ network for the one-time build (cached in `~/.cache/aql-divergence`).

## Background: what this guards against

`aql --compile` is documented to return results identical to the interpreter
(it falls back to the interpreter for anything it can't lower). This harness
exists because that promise — "opt-in performance, never semantics" — is the
one a sorting library most depends on: every algorithm must produce the same
ordering whether interpreted or compiled. The keystone property test
(cross-agreement: every algorithm equals the stable `Sort.merge`) runs under
both surfaces here, so a compiler divergence on any algorithm would surface
as a `DIVERGE` row.

`--force-compile` refuses on code-body words (`each` / `do` / the test-
framework words, "Stage 2") and falls back cleanly under `--compile` — sound
by `aql-lang/aql`'s `design/COMPILABLE-SUBSET.md` ("refusal is always sound;
the worst failure mode is slow, not wrong").

### Wiring it into CI

`run.sh` is self-contained, so a gating job is one block (it is already in
`ci/test.yml`, pending promotion to `.github/workflows/` by a token with
`workflow` scope):

```yaml
  divergence:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.24'
      - name: interpreter / byte-compiler agreement (check advisory)
        run: test/divergence/run.sh
```
