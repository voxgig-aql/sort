#!/bin/bash
# SessionStart hook: ensure the `aql` interpreter is available so the agent can
# run this library's scripts and tests. AQL has no tagged release, so we build
# it from source at the commit this library is pinned to (the same ref CI uses).
#
# Synchronous and idempotent: skips the build if the binary already exists, and
# caches into the container so later sessions are instant. Progress goes to
# stderr; stdout is left clean (SessionStart stdout is injected as context).
set -uo pipefail

# Web sessions are the target; locally a developer already has aql. No-op
# elsewhere. (Remove this guard to build everywhere.)
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

log() { echo "[session-start] $*" >&2; }

# Keep this in lockstep with the workflow's AQL_REF (the consistency CI job
# fails if they drift). The canonical workflow currently lives in ci/test.yml
# pending promotion to .github/workflows/ (see ci/README.md). Full 40-char
# commit so the build is reproducible. This is the latest aql `main` at the
# time the module was written; re-pinned 2026-07-11.
AQL_REF=0721e8280e01a37174c41b99ab49799f3098c135
BIN_DIR="$HOME/.local/bin"
AQL="$BIN_DIR/aql"

# Persist PATH for the rest of the session.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
export PATH="$BIN_DIR:$PATH"

if command -v aql >/dev/null 2>&1 || [ -x "$AQL" ]; then
  log "aql already present ($("$AQL" -version 2>/dev/null || aql -version 2>/dev/null)); skipping build."
else
  if ! command -v go >/dev/null 2>&1; then
    log "WARNING: Go toolchain not found; cannot build aql. Install Go, or build aql manually (see docs/how-to.md)."
    exit 0
  fi
  log "Building aql @ $AQL_REF from source (one-time; cached afterwards)…"
  mkdir -p "$BIN_DIR"

  # The Go-module-proxy pseudo-version for the SAME commit (12-hex suffix is
  # the short SHA of AQL_REF) — used by the proxy fallback below. Bump with
  # AQL_REF.
  AQL_GOPROXY_VERSION=v0.0.0-20260711120450-0721e8280e01

  # Reconstruct + build from the Go module proxy (3 nested modules). Reachable
  # where GitHub egress (git clone / codeload) is blocked but proxy.golang.org
  # is allowed. Args: <out-binary> <workdir>.
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
        -ldflags "-X github.com/aql-lang/aql/cmd/go.Version=$AQL_REF" \
        -o "$out" ./aql )
  }

  src="$(mktemp -d)"
  # Try the codeload tarball first; on failure fall back to the Go module proxy.
  if curl -fsSL "https://codeload.github.com/aql-lang/aql/tar.gz/$AQL_REF" \
       | tar -xz -C "$src" --strip-components=1 \
     && ( cd "$src/cmd/go" \
          && GOFLAGS=-mod=mod go build \
               -ldflags "-X github.com/aql-lang/aql/cmd/go.Version=${AQL_REF}" \
               -o "$AQL" ./aql ); then
    log "Built $("$AQL" -version 2>/dev/null)."
  else
    log "codeload path failed; trying the Go module proxy…"
    rm -rf "$src"; src="$(mktemp -d)"
    if build_from_goproxy "$AQL" "$src"; then
      log "Built $("$AQL" -version 2>/dev/null) (via Go module proxy)."
    else
      log "WARNING: aql build failed (codeload and Go proxy); see docs/how-to.md."
    fi
  fi
  rm -rf "$src"
fi

# Fast confidence check: run the smoke test if aql is usable. Never fail the
# session on a check error.
if [ -x "$AQL" ] && [ -f "$CLAUDE_PROJECT_DIR/test/sort_smoke_test.aql" ]; then
  if ( cd "$CLAUDE_PROJECT_DIR" && "$AQL" test/sort_smoke_test.aql >/dev/null 2>&1 ); then
    log "Smoke check passed (aql test/sort_smoke_test.aql)."
  else
    log "NOTE: smoke check did not pass; toolchain may be incomplete."
  fi
fi

exit 0
