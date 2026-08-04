# Performance baseline snapshot

Reference numbers for the Sort library, produced by `bench/run.sh` (see
that script and `bench/sort_bench.aql` for the workload). Reproduce with:

```bash
boru=/path/to/aql bench/run.sh
```

**These numbers are indicative, not absolute.** They were measured in a
shared cloud container under variable load, at small sizes chosen so the
(slow) interpreter finishes in seconds. Their value is *relative*: ranking
the algorithms and tracking the interpreter-vs-bytecode gap across boru
versions — not comparing boru against a native sort. boru threads a
first-class comparator function through every element move, and that
per-comparison dispatch, not the algorithm, dominates the wall-clock.

This snapshot was taken with the branch build of boru (latest `main`, the
check-mode return-count fix, and the definition-site analysis-quota fix
that lets the whole library `--force-compile` without refusal); the bench
runs with `AQL_NO_CHECK=1`, so its runtime timings are representative of
the module's pinned `6185620` build too. The `bucket` / `shell` rows in
particular reflect the `flex[0]`+`set` index-cursor refactor, which is a
library change independent of the boru version.

## Snapshot — n_small=200 / n_large=800, best-of-2, 30s cap

```
ALGORITHM      INTERP_MS   COMPILED_MS    SPEEDUP
insertion        12119.0         829.0      14.6x
selection         4492.0         848.0       5.3x
bubble            8514.0        1582.0       5.4x
shell               >30s        9397.0          -
comb              7032.0        1666.0       4.2x
quick               >30s         374.0          -
merge            18898.0         465.0      40.6x
heap             10421.0         625.0      16.7x
intro               >30s         363.0          -
tim                 >30s             -          -
sort                >30s         466.0          -
counting           837.0          50.0      16.7x
radix-lsd         2808.0          94.0      29.9x
bucket            1471.0          67.0      22.0x
```

(`INTERP_MS` = interpreter, `AQL_NO_COMPILE=1`; `COMPILED_MS` = bytecode
VM, the default; `>30s` = the interpreter run exceeded the per-run cap; a
`-` = no number, see notes.)

## What the numbers say

- **The bytecode VM is the mode that matters.** It is 4–40× faster than
  the interpreter here; the interpreter is impractically slow for the
  O(n log n) sorts at n=800 (quick / intro / shell / sort / tim run tens
  of seconds or overrun the cap). Run library code with `boru` (compile is
  the default) or `boru --compile`, never `AQL_NO_COMPILE=1`.
- **`sort` (the recommended default, a stable merge sort), `merge`,
  `radix-lsd`, `counting`, and `bucket` all lower cleanly and fly.**
- **`bucket` now shows ~22×** (67 ms compiled vs 1471 ms interpreted):
  earlier it did not lower — its inner loop kept a one-cell index cursor
  as `flex [i]`, whose list body reads the enclosing `each` frame's
  iterator through dynamic scope, which the byte compiler could not bind
  through the closure (`--compile` silently fell back to the interpreter,
  ~1.0×). Building the cursor empty and inert — `flex[0]` then `set` — lets
  the body lower; `shell` carried the same shape and the same fix.
- **The whole library and every test suite now `--force-compile` with no
  refusal.** That additionally needed an boru fix: the per-fn analysis
  quota was keyed by bare fn name, so every higher-order `each$body`
  closure across the program shared one budget and a 64-plus-closure
  module bailed later loops to an unresolvable `Any` (a "code-body word
  each (Stage 2)" refusal). Keying the quota by definition site fixes it.
  Both surfaces always produced identical, correct output; this closes the
  `--force-compile` gap the divergence harness's advisory column noted.
- **`tim` has no compiled number**: at n≥500 its run-detection + merge is
  step-heavy enough to exceed boru's default runtime step budget (10M) and
  raise `evaluation_limit`. It is correct (the property suite cross-checks
  it against `merge`) but its constant factor is high in this
  implementation — a candidate for a future library optimisation.
- Distribution sorts use a **bounded value range** (≈ O(n)); with a
  million-wide range, `counting`/`bucket` would measure the range (they
  are O(n + range)) and blow the step budget, so the harness caps it.
