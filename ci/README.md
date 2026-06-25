# ci/ — staged GitHub Actions workflow

GitHub blocks pushes that **create or update files under
`.github/workflows/`** unless the pushing token carries the `workflow` OAuth
scope. The automation that maintains this repo doesn't have that scope, so
workflow changes are staged here and a maintainer promotes them.

## What's here

- **`test.yml`** — the intended `.github/workflows/test.yml`. It is the
  canonical, up-to-date workflow; the copy currently under
  `.github/workflows/` is **stale** (it pins an older, drifted `AQL_REF` and
  still runs the previous module's suites) and is superseded by this one.

### What changed vs the live `.github/workflows/test.yml`

1. **`AQL_REF` bumped to `12a44e0…`** — the latest aql `main` commit, the
   one this library is verified against (every suite interprets and byte
   compiles to identical output).
2. **Suites renamed** to `test/sort_*` and the static check points at
   `sort.aql`.
3. **`divergence` job** runs `test/divergence/run.sh`. The interpreter and
   byte compiler are gating; `aql check` is **advisory** here (its static
   analysis has known false positives on the first-class comparator
   functions this library threads through every sort). Self-contained
   (builds its own aql via a `codeload` tarball).
4. **`consistency` job** checks the renamed `sort-aql` skill/plugin paths,
   the JSON manifests, and that `AQL_REF` agrees across the hook,
   `test/divergence/run.sh`'s `AQL_BYTECODE_REF`, and `api.json`'s prefix.

## Promoting it (maintainer, one-time)

From a clone with `workflow` scope (e.g. a local checkout authenticated with a
PAT that has `workflow`, or the GitHub web UI):

```bash
git mv ci/test.yml .github/workflows/test.yml
git commit -m "ci: adopt aql 12a44e0; run sort suites"
git push
```

(Or copy the contents over the existing file in the GitHub web editor.) Once
promoted, the `ci/` folder can be removed. Until then, treat `ci/test.yml` as
the source of truth; the consistency check inside it reads its own `env.AQL_REF`,
so it is correct the moment it lands under `.github/workflows/`.
