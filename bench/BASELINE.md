# Performance baseline snapshot

Reference numbers for the Sort library, produced by `bench/run.sh` (see
that script and `bench/sort_bench.aql` for the workload). Reproduce with:

```bash
AQL=/path/to/aql bench/run.sh
```

**These numbers are indicative, not absolute.** They were measured in a
shared cloud container under variable load, at small sizes chosen so the
(slow) interpreter finishes in seconds. Their value is *relative*: ranking
the algorithms and tracking the interpreter-vs-bytecode gap across aql
versions — not comparing AQL against a native sort. AQL threads a
first-class comparator function through every element move, and that
per-comparison dispatch, not the algorithm, dominates the wall-clock.

This snapshot was taken with aql @ `2afef08` (latest `main` plus a
check-mode-only fix); the bench runs with `AQL_NO_CHECK=1`, so its runtime
timings are representative of the module's pinned `7b1a4fb` build too.

## Snapshot — aql @ 2afef08, n_small=200 / n_large=800, best-of-2, 25s cap

```
ALGORITHM      INTERP_MS   COMPILED_MS    SPEEDUP
insertion         8585.0         503.0      17.1x
selection         2810.0         481.0       5.8x
bubble            4976.0        1181.0       4.2x
shell               >25s        5510.0          -
comb              3948.0         976.0       4.0x
quick               >25s         242.0          -
merge            12086.0         303.0      39.9x
heap              7057.0         465.0      15.2x
intro               >25s         236.0          -
tim                 >25s             -          -
sort             22262.0         256.0      87.0x
counting           573.0          31.0      18.5x
radix-lsd         2176.0          63.0      34.5x
bucket             935.0         897.0       1.0x
```

(`INTERP_MS` = interpreter, `AQL_NO_COMPILE=1`; `COMPILED_MS` = bytecode
VM, the default; `>25s` = the interpreter run exceeded the per-run cap; a
`-` = no number, see notes.)

## What the numbers say

- **The bytecode VM is the mode that matters.** It is 4–87× faster than
  the interpreter here; the interpreter is impractically slow for the
  O(n log n) sorts at n=800 (quick / intro / shell / sort / tim run tens
  of seconds or overrun the cap). Run library code with `aql` (compile is
  the default) or `aql --compile`, never `AQL_NO_COMPILE=1`.
- **`sort` (the recommended default, a stable merge sort) compiles best**
  — 87× — and `merge` / `radix-lsd` / `counting` also lower cleanly and
  fly.
- **`bucket` shows ~1.0×** (897 ms compiled vs 935 ms interpreted): its
  body does not fully lower — a nested `each` closure reads a `def`-local
  bound in an enclosing `each` frame, which the byte compiler cannot
  resolve yet — so `--compile` silently falls back to the interpreter and
  there is no speedup. `radix-msd` shares the shape. This is a known aql
  byte-compiler coverage gap (the same one the divergence harness reports
  as a `--force-compile` refusal on the smoke suite), not a library bug —
  both surfaces produce identical, correct output.
- **`tim` has no compiled number**: at n≥500 its run-detection + merge is
  step-heavy enough to exceed aql's default runtime step budget (10M) and
  raise `evaluation_limit`. It is correct (the property suite cross-checks
  it against `merge`) but its constant factor is high in this
  implementation — a candidate for a future library optimisation.
- Distribution sorts use a **bounded value range** (≈ O(n)); with a
  million-wide range, `counting`/`bucket` would measure the range (they
  are O(n + range)) and blow the step budget, so the harness caps it.
