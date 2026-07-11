#!/usr/bin/env bash
# Performance baseline runner for the Sort library.
#
# Times each representative algorithm sorting a fixed, deterministic
# pseudo-random Integer array under both aql execution surfaces —
#   interpreter    AQL_NO_COMPILE=1 aql …      (the slow reference)
#   bytecode VM    aql --compile …             (the default)
# — and prints a table with the interpreter/compiled speedup.
#
# Each (algorithm, surface) runs as its OWN aql process, best-of REPS,
# with a per-run timeout: aql block-buffers stdout when piped, so a run
# that overran a shared budget would lose its output — a dedicated process
# per cell flushes at exit and a slow cell is marked `>Ns` rather than
# hanging or corrupting the table. The interpreter is ~15x slower than the
# VM and super-linear here (per-element comparator dispatch dominates), so
# some interpreter cells legitimately time out at these sizes; the compiled
# column is the practical baseline.
#
# Usage:  AQL=/path/to/aql bench/run.sh [reps]        # default reps=3
#         BENCH_TIMEOUT=45 …                          # per-run seconds
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
AQL="${AQL:-aql}"
reps="${1:-3}"
to="${BENCH_TIMEOUT:-45}"

command -v "$AQL" >/dev/null 2>&1 || { echo "run.sh: aql not found (set AQL=/path/to/aql)" >&2; exit 1; }

SMALL=200      # O(n^2) / sub-quadratic family
LARGE=800      # O(n log n) / distribution family

# name size kind    (kind: cmp = comparator sort via Sort.by-number; dist = no comparator)
ALGOS=(
  "insertion $SMALL cmp"  "selection $SMALL cmp"  "bubble $SMALL cmp"
  "shell $SMALL cmp"      "comb $SMALL cmp"
  "quick $LARGE cmp"      "merge $LARGE cmp"      "heap $LARGE cmp"
  "intro $LARGE cmp"      "tim $LARGE cmp"        "sort $LARGE cmp"
  "counting $LARGE dist"  "radix-lsd $LARGE dist" "bucket $LARGE dist"
)

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# gen <name> <size> <kind> : write a one-algorithm timed program to $tmp/prog.aql.
# The value range is chosen per family: comparison sorts get a near-distinct
# range (few duplicates — the interesting case), while distribution sorts get a
# range of ~O(n) because counting / bucket cost is O(n + range), so a million-
# wide range would measure the range, not the sort (and blow the runtime step
# budget building a million-cell tally).
gen() {
  local name="$1" size="$2" kind="$3" call span
  if [ "$kind" = dist ]; then call="a Sort.$name end"; span=4000; else call="a Sort.$name Sort.by-number end"; span=1000000; fi
  cat > "$tmp/prog.aql" <<EOF
import "$repo/sort.aql" end
import "aql:time-util" end
def a (iota $size each [ var [[i] ((i mul 2654435761) mod $span) ] ])
def t (TimeUtil.now) def _ ($call) print ((TimeUtil.total-ms (TimeUtil.elapsed t))) end
EOF
}

# best_of <env/cmd...> : run $tmp/prog.aql `reps` times, echo the min ms, or ""
# when every rep timed out or produced no number.
best_of() {
  local r best="" ms rc
  for ((r=0; r<reps; r++)); do
    ms="$(timeout "$to" "$@" "$tmp/prog.aql" 2>/dev/null | tail -1)"; rc=$?
    [ $rc -ne 0 ] && continue
    case "$ms" in ''|*[!0-9.]*) continue ;; esac
    if [ -z "$best" ] || awk "BEGIN{exit !($ms < $best)}"; then best="$ms"; fi
  done
  echo "$best"
}

echo "# aql: $("$AQL" -version 2>&1)"
echo "# n_small=$SMALL n_large=$LARGE  reps=$reps (best-of)  timeout=${to}s  execution-only ms"
printf '%-11s  %11s  %12s  %9s\n' ALGORITHM INTERP_MS COMPILED_MS SPEEDUP
printf '%-11s  %11s  %12s  %9s\n' ----------- ----------- ------------ ---------
for spec in "${ALGOS[@]}"; do
  read -r name size kind <<<"$spec"
  gen "$name" "$size" "$kind"
  echo "# … $name (n=$size)" >&2
  i="$(best_of env AQL_NO_CHECK=1 AQL_NO_COMPILE=1 "$AQL")"
  c="$(best_of env AQL_NO_CHECK=1 "$AQL" --compile)"
  sp="-"
  if [ -n "$i" ] && [ -n "$c" ]; then sp="$(awk "BEGIN{ if ($c>0) printf \"%.1fx\", $i/$c }")"; fi
  printf '%-11s  %11s  %12s  %9s\n' "$name" "${i:-">${to}s"}" "${c:--}" "$sp"
done
