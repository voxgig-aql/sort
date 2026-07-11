#!/usr/bin/env bash
# Run every test suite through all three aql execution surfaces:
#
#   interpreter   aql X                  the default — what CI and users run
#   check         aql check X            static type-check (ADVISORY here)
#   byte compiler aql --compile X        bytecode when compilable, else a SILENT
#                                        fallback to the interpreter; documented
#                                        to be IDENTICAL to it ("opt-in
#                                        performance, never semantics")
#
# Plus an informational `aql --force-compile X` line per suite — how much of
# each program the emitter can fully lower today (refusals there are expected
# coverage gaps; under --compile they fall back, so they are not failures).
#
# GATING: a non-zero interpreter run, or any difference between `aql --compile
# X` and `aql X`, fails the script. On the pinned aql the suites are also
# fully CHECK-clean (0 errors) — and note that on this build a `check` error is
# fatal to the interpreter anyway, so a clean interpreter run already implies a
# clean check. The `check` column is reported but kept non-gating as a soft
# signal; the hard guarantee is interpreter == byte compiler.
#
# This harness builds its OWN aql at the ref below (it equals the library's
# pin, but pinning it here keeps the harness self-contained — it never depends
# on whatever aql is on PATH). Cached under ~/.cache/aql-divergence; needs `go`
# + network for the one-time build. It fetches the source from the GitHub
# codeload tarball, and FALLS BACK to the Go module proxy when GitHub egress is
# blocked (as some sandboxes block git clone / codeload but allow
# proxy.golang.org).
set -uo pipefail

# aql-lang/aql @ main, 2026-07-11 — the latest commit the library pins. Bump in
# lockstep with the workflow AQL_REF.
AQL_BYTECODE_REF=0721e8280e01a37174c41b99ab49799f3098c135

# The Go-module-proxy pseudo-version for the SAME commit (its 12-hex suffix is
# the short SHA of AQL_BYTECODE_REF). Used by the proxy fallback below when the
# GitHub codeload tarball is blocked. Bump alongside AQL_BYTECODE_REF.
AQL_GOPROXY_VERSION=v0.0.0-20260711120450-0721e8280e01

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
CACHE="$HOME/.cache/aql-divergence"
AQL="$CACHE/aql-$AQL_BYTECODE_REF"

# Build aql from the Go module proxy — reconstruct the 3 nested modules
# (eng/go, lang/go, cmd/go; the binary's cmd/go replaces ../../{eng,lang}/go)
# then `go build`. Works where GitHub egress (git clone / codeload) is blocked
# but proxy.golang.org is reachable. Args: <out-binary> <workdir>.
build_from_goproxy() {
  local out="$1" work="$2" sub
  mkdir -p "$work/tree"
  for sub in eng/go lang/go cmd/go; do
    curl -fsSL -o "$work/m.zip" \
      "https://proxy.golang.org/github.com/aql-lang/aql/$sub/@v/$AQL_GOPROXY_VERSION.zip" || return 1
    ( cd "$work" && unzip -q -o m.zip ) || return 1
    mkdir -p "$work/tree/$sub"
    cp -a "$work/github.com/aql-lang/aql/$sub@$AQL_GOPROXY_VERSION/." "$work/tree/$sub/" || return 1
    rm -rf "$work/github.com" "$work/m.zip"
  done
  ( cd "$work/tree/cmd/go" && GOFLAGS=-mod=mod go build \
      -ldflags "-X github.com/aql-lang/aql/cmd/go.Version=$AQL_BYTECODE_REF" \
      -o "$out" ./aql )
}

SUITES="
test/sort_unit_test.aql
test/sort_unit_spec.aql
test/sort_prop_test.aql
test/sort_prop_spec.aql
test/sort_smoke_test.aql
"

log() { echo "[divergence] $*"; }

# --- build aql at the bytecode-capable ref -------------------------------
# Try the GitHub codeload tarball first; if that is blocked (403 / egress
# policy), fall back to reconstructing from the Go module proxy.
if [ ! -x "$AQL" ]; then
  command -v go >/dev/null 2>&1 || { echo "error: Go toolchain not found." >&2; exit 1; }
  log "building aql @ $AQL_BYTECODE_REF (one-time; cached) …"
  mkdir -p "$CACHE"
  src="$(mktemp -d)"
  if curl -fsSL "https://codeload.github.com/aql-lang/aql/tar.gz/$AQL_BYTECODE_REF" \
       | tar -xz -C "$src" --strip-components=1 \
     && ( cd "$src/cmd/go" && GOFLAGS=-mod=mod go build \
            -ldflags "-X github.com/aql-lang/aql/cmd/go.Version=$AQL_BYTECODE_REF" \
            -o "$AQL" ./aql ); then
    :
  else
    log "codeload path failed; falling back to the Go module proxy …"
    rm -rf "$src"; src="$(mktemp -d)"
    build_from_goproxy "$AQL" "$src" || { echo "error: build failed (codeload and Go proxy)." >&2; rm -rf "$src"; exit 1; }
  fi
  rm -rf "$src"
fi
log "aql: $("$AQL" -version)"
echo

cd "$REPO"
fail=0

# --- three modes, per suite ----------------------------------------------
# INTERPRETER and BYTECODE are gating; CHECK is advisory (see header).
log "interpreter / check / --compile (interpreter & bytecode gate; check advisory):"
printf '  %-28s  %-12s  %-16s  %s\n' SUITE INTERPRETER CHECK BYTECODE
for s in $SUITES; do
  name="$(basename "$s")"

  interp="$("$AQL" "$s" 2>&1)"; irc=$?
  if [ $irc -eq 0 ]; then i_col="ok"; else i_col="FAIL"; fail=1; fi

  errs="$("$AQL" check "$s" 2>&1 | grep -oE '[0-9]+ error' | grep -oE '[0-9]+' | head -1)"
  errs="${errs:-0}"
  # Advisory: report the count but never gate on it.
  if [ "$errs" = 0 ]; then c_col="ok"; else c_col="advisory($errs)"; fi

  comp="$("$AQL" --compile "$s" 2>&1)"
  if [ "$interp" = "$comp" ]; then b_col="ok"; else b_col="DIVERGE"; fail=1; fi

  printf '  %-28s  %-12s  %-16s  %s\n' "$name" "$i_col" "$c_col" "$b_col"
  if [ "$b_col" = DIVERGE ]; then
    diff <(printf '%s\n' "$interp") <(printf '%s\n' "$comp") | sed 's/^/      /'
  fi
done

# --- coverage: how much does --force-compile actually lower? --------------
echo
log "--force-compile coverage (refusals are expected gaps, not failures):"
for s in $SUITES; do
  out="$("$AQL" --force-compile "$s" 2>&1)"
  if printf '%s\n' "$out" | grep -q 'force-compile:'; then
    printf '  %-28s  refused  — %s\n' "$(basename "$s")" "$(printf '%s\n' "$out" | grep -o 'force-compile:.*' | head -1)"
  else
    printf '  %-28s  compiled\n' "$(basename "$s")"
  fi
done

echo
if [ "$fail" = 0 ]; then
  log "PASS — every suite runs clean under the interpreter and the byte compiler agrees (check advisory)."
else
  log "FAIL — a suite errored or the byte compiler diverged from the interpreter."
fi
exit $fail
