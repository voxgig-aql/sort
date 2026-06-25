# sort

A dependency-light **sorting library** implemented in
[AQL](https://github.com/aql-lang/aql) — every well-known sorting
algorithm, over every AQL type, driven by composable **comparators**.
Sorts return a new sorted list and never mutate their input.

```aql
import "./sort.aql"

print (([5 3 8 1] Sort.quick Sort.by-number end)) end                # => [1, 3, 5, 8]
print ((["file10" "file2" "file1"] Sort.merge Sort.natural end)) end # => ['file1', 'file2', 'file10']
print (([170 45 75 2 802 24] Sort.radix-lsd end)) end                # => [2, 24, 45, 75, 170, 802]
```

> **Forking this to build a new AQL library?** This repo is a GitHub
> template — read **[TEMPLATE.md](TEMPLATE.md)** for the instantiation
> checklist, then delete it.

> **Calling this library from an AI coding agent?** Read
> **[AGENTS.md](AGENTS.md)** first — the exact AQL calling convention,
> verified idioms, and common mistakes. (Claude Code auto-loads it via
> `CLAUDE.md`; a portable skill lives in
> [`.claude/skills/sort-aql`](.claude/skills/sort-aql/SKILL.md).)

## What you get

- **Comparison sorts** — `quick`, `merge` (stable), `heap`, `intro`,
  `tim` (stable), `insertion`, `selection`, `bubble`, `shell`, `comb`,
  `cocktail`, `gnome`, `cycle`, `odd-even`, `pancake`, `bitonic`.
- **Distribution sorts** (Integers, no comparator) — `counting`,
  `pigeonhole`, `radix-lsd`, `radix-msd`, `bucket`, `bead`.
- **Joke / educational sorts** — `bogo`, `stooge`, `slow`.
- **Comparators** — `by-number`, `by-string`, `by-boolean`,
  `by-generic`, `natural` (alphanumeric, so `"file2" < "file10"`),
  `case-insensitive`, plus the combinators `reverse` and `by-key`.

Sort anything by supplying a comparator — a two-argument function
returning a negative/zero/positive `Integer`, the same contract as the
built-in `cmp`:

```aql
def by-len fn [[b:Any a:Any] [Integer] [ (a size) (b size) cmp ]]
print ((["bbb" "a" "cc"] Sort.merge by-len/r end)) end   # => ['a', 'cc', 'bbb']
```

## Documentation

The docs follow the [Diátaxis](https://diataxis.fr) framework — four
modes, each serving a different need. Start wherever your need is:

| | Mode | Read this when you want to… |
|--|------|----------------------------|
| 🎓 | **[Tutorial](docs/tutorial.md)** | learn by sorting your first list step by step |
| 🔧 | **[How-to guides](docs/how-to.md)** | accomplish a specific task (custom order, natural sort, by-key…) |
| 📖 | **[Reference](docs/reference.md)** | look up exact words, return types, stability, complexity |
| 💡 | **[Explanation](docs/explanation.md)** | understand the comparator-driven design and why it's built this way |

New here? Read the [Tutorial](docs/tutorial.md). Already know your
algorithms and just want the API? Jump to the [Reference](docs/reference.md).

## The `Sort` API at a glance

| Call | Purpose |
|------|---------|
| `list Sort.<algo> comparator` | sort with a comparison algorithm → new sorted List |
| `list Sort.<algo>`            | sort Integers with a distribution sort (no comparator) |
| `a b Sort.by-number`          | a comparator: negative / zero / positive Integer |
| `comp Sort.reverse`           | a comparator that reverses `comp` (descending) |
| `keyfn Sort.by-key`           | a comparator that orders by a derived key |
| `list Sort.is-sorted comparator` | test whether a list is ordered → Boolean |

Every call ends with `end` (or is wrapped in parens). Full details are in
the [Reference](docs/reference.md).

## For AI coding agents

If an agent will call this library, point it at **[AGENTS.md](AGENTS.md)**
— the exact AQL calling convention, verified idioms, and the common
mistakes to avoid.

To make that guidance available in *another* project that uses this
library, install the bundled skill either way:

- **Copy the skill** — drop
  [`.claude/skills/sort-aql/`](.claude/skills/sort-aql/SKILL.md)
  into that project's `.claude/skills/` (or your `~/.claude/skills/`). It
  loads on demand whenever `Sort` calls appear.
- **Install the plugin** — this repo is also a plugin marketplace:

  ```
  /plugin marketplace add voxgig-aql/sort
  /plugin install sort-aql@voxgig-aql
  ```

Working inside *this* repo, Claude Code picks the guidance up
automatically via `CLAUDE.md` (which imports `AGENTS.md`) and the bundled
skill.

## Project layout

```
sort.aql                  the library (the Sort namespace: comparators + algorithms)
AGENTS.md                 agent guide: how to call this library correctly
test/sort_unit_test.aql   example-based unit tests — direct (Test.test)
test/sort_unit_spec.aql   example-based unit tests — declarative spec format
test/sort_prop_test.aql   property-based tests — direct (Test.check-prop)
test/sort_prop_spec.aql   property-based tests — declarative spec format
test/sort_smoke_test.aql  end-to-end smoke run over every public word
test/divergence/          three-surface guard (interpreter · check · byte compiler)
docs/                     Diátaxis documentation (above)
```

Test files follow a consistent naming convention: `_test.aql` for
direct tests (unit or property), `_spec.aql` for declarative specs (unit
or property). The keystone property is **cross-agreement** — every
algorithm must return the same ordering as the stable `Sort.merge`.

## Running it

Build the `aql` interpreter, then run any script or test — see
[How-to → Install and run](docs/how-to.md#install-and-run-aql) and
[Run the tests](docs/how-to.md#run-the-tests):

```bash
aql test/sort_unit_test.aql   # unit tests — direct
aql test/sort_unit_spec.aql   # unit tests — declarative spec format
aql test/sort_prop_test.aql   # property tests — direct
aql test/sort_prop_spec.aql   # property tests — declarative spec format
aql test/sort_smoke_test.aql  # end-to-end smoke run
```

A GitHub Actions workflow
([`.github/workflows/test.yml`](.github/workflows/test.yml)) builds aql from a
pinned commit and runs every suite — plus a `consistency` job (agent-skill
drift, JSON manifests, and a pinned-ref guard) — on each push and pull request.

## License

See [LICENSE](LICENSE).
