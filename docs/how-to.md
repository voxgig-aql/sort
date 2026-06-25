# How-to guides

Task-oriented recipes. Each one assumes you already know roughly how a
sort is called; if not, start with the [Tutorial](tutorial.md). For the
*why* behind any of these, follow the links into the
[Explanation](explanation.md); for exact signatures, the
[Reference](reference.md).

- [Install and run aql](#install-and-run-aql)
- [Sort by a custom comparator](#sort-by-a-custom-comparator)
- [Sort in descending order](#sort-in-descending-order)
- [Sort by a key](#sort-by-a-key)
- [Sort filenames in natural order](#sort-filenames-in-natural-order)
- [Sort strings case-insensitively](#sort-strings-case-insensitively)
- [Choose an algorithm](#choose-an-algorithm)
- [Use a distribution sort](#use-a-distribution-sort)
- [Handle errors](#handle-errors)
- [Run the tests](#run-the-tests)

---

## Install and run aql

The module is written in AQL, which has no tagged release yet, so build
the interpreter from source (the documented `go install …/aql@latest`
fails on the repo's replace directives). A plain `git clone` may be
blocked, so fetch the pinned commit as a codeload tarball:

```bash
mkdir -p /tmp/aql-source
curl -fsSL https://codeload.github.com/aql-lang/aql/tar.gz/c5fbb041b65ceab442b1df16e84a88b9365d71d8 \
  | tar -xz -C /tmp/aql-source --strip-components=1
cd /tmp/aql-source/cmd/go
GOFLAGS=-mod=mod go build -o "$HOME/.local/bin/aql" ./aql
```

Make sure `$HOME/.local/bin` is on your `PATH`, then check it:

```bash
aql -version
# => aql c5fbb041b65ceab442b1df16e84a88b9365d71d8
```

Run any script in this repo by passing its path:

```bash
aql test/sort_smoke_test.aql
```

This module is verified against aql commit `c5fbb04`; the CI workflow
pins the same commit.

---

## Sort by a custom comparator

A comparator is a two-argument function value returning a negative / zero
/ positive Integer when the first item sorts before / equal to / after the
second. Define one with `fn` and pass it with a **`/r`** suffix so it is
handed over as a value rather than invoked on the spot:

```aql
import "./sort.aql"

def by-length fn [
  [b:Any a:Any] [Integer] [ (a size) (b size) cmp ]
]

print ((["bbb" "a" "cc"] Sort.merge by-length/r end)) end
# => ["a", "cc", "bbb"]
```

Write the body in terms of `a` (the earlier item) and `b` (the later one),
and defer to the native `cmp` rather than subtracting — `cmp` is a
three-way compare with no overflow risk. To order records by a field:

```aql
def by-second fn [
  [b:Any a:Any] [Integer] [ (a get 1) (b get 1) cmp ]
]
print (([[1 30] [2 10] [3 20]] Sort.merge by-second/r end)) end
# => [[2, 10], [3, 20], [1, 30]]
```

(Why your comparator must live in the running module — and why `/r`:
[Explanation → Function values and `/r`](explanation.md#function-values-and-r).)

---

## Sort in descending order

Don't write a second, reversed comparator — wrap an existing one with the
`Sort.reverse` combinator. It takes a comparator and returns a new one
that reverses its verdict:

```aql
print (([5 3 8 1 9 2] Sort.quick (Sort.by-number Sort.reverse) end)) end
# => [9, 8, 5, 3, 2, 1]
```

`reverse` composes with any comparator, including ones you build:

```aql
def by-length fn [[b:Any a:Any] [Integer] [ (a size) (b size) cmp ]]
print ((["bbb" "a" "cc"] Sort.merge (by-length/r Sort.reverse) end)) end
# => ["bbb", "cc", "a"]
```

---

## Sort by a key

Often you want to order items by some derived value (a field, a length, a
computed score) rather than by the items themselves. `Sort.by-key` takes a
**key function** — one argument in, the key out — and returns a comparator
that orders items by their keys (compared with the native `cmp`):

```aql
def length-of fn [[s:Any] [Integer] [ s size ]]
print ((["bbb" "a" "cc"] Sort.merge (length-of/r Sort.by-key) end)) end
# => ["a", "cc", "bbb"]
```

The key function is your own word, so pass it with `/r`. `by-key`
composes with `reverse` for a descending key order:
`(length-of/r Sort.by-key) Sort.reverse`.

---

## Sort filenames in natural order

Plain lexicographic order puts `"file10"` before `"file2"` (digit `1`
precedes `2`). `Sort.natural` compares embedded runs of digits by their
**numeric value** instead, which is almost always what you want for
filenames, versions, and labels:

```aql
print ((["file10" "file2" "file1"] Sort.merge Sort.natural end)) end
# => ["file1", "file2", "file10"]
```

It handles digit runs anywhere in the string, so `"x9"` sorts before
`"x10"` too.

---

## Sort strings case-insensitively

`Sort.by-string` is case-sensitive — every uppercase letter sorts before
every lowercase one. For a case-folded order, use `Sort.case-insensitive`:

```aql
print ((["HELLO" "abc" "Zebra"] Sort.merge Sort.case-insensitive end)) end
# => ["abc", "HELLO", "Zebra"]
```

It lowercases both operands before comparing, so `"abc"`, `"HELLO"`, and
`"Zebra"` order as `a < h < z`.

---

## Choose an algorithm

All the comparison sorts produce the same ordering; they differ in speed,
stability, and pedigree. Reach for these in practice:

| Goal | Use |
|------|-----|
| A sensible general-purpose default | `Sort.sort` (stable merge sort) |
| Stable order (equal items keep input order) | `Sort.merge` or `Sort.tim` |
| Fast, in-place, average case | `Sort.quick` |
| Guaranteed O(n log n) worst case | `Sort.heap` or `Sort.intro` |
| Nearly-sorted input | `Sort.tim` or `Sort.insertion` |
| Integers only, want to skip comparisons | a distribution sort (below) |

The remaining comparison sorts — `bubble`, `selection`, `gnome`,
`cocktail`, `comb`, `shell`, `odd-even`, `cycle`, `pancake`, `bitonic` —
are correct and useful for study, but for production data prefer the rows
above. The joke sorts (`bogo`, `stooge`, `slow`) are deliberately
inefficient and exist for demonstration only. The full complexity and
stability table is in the [Reference](reference.md#comparison-sorts).

```aql
print (([5 3 8 1 9 2] Sort.sort Sort.by-number end)) end   # => [1, 2, 3, 5, 8, 9]
print (([5 3 8 1 9 2] Sort.tim  Sort.by-number end)) end   # => [1, 2, 3, 5, 8, 9]
```

---

## Use a distribution sort

When your data is **Integers**, the distribution sorts skip comparisons
entirely and order by counting or bucketing. They take **no comparator**
and always sort ascending:

```aql
print (([170 45 75 90 2 802 24 66] Sort.radix-lsd end)) end
# => [2, 24, 45, 66, 75, 90, 170, 802]
```

`Sort.counting` and `Sort.pigeonhole` also accept **negative** Integers:

```aql
print (([5 -2 8 -1 0] Sort.counting end)) end
# => [-2, -1, 0, 5, 8]
```

`Sort.radix-lsd`, `Sort.radix-msd`, and `Sort.bead` require
**non-negative** Integers; `Sort.bucket` accepts any Integers. All raise
`bad_input` on a non-Integer element (and the radix/bead family on a
negative one) — see the next recipe. (Why these beat comparison sorts on
the right data:
[Explanation → Distribution sorts](explanation.md#why-distribution-sorts-need-no-comparator).)

---

## Handle errors

Failures raise coded errors. Wrap the call in `do … error …`; inside the
handler the Error value is on the stack, with `code` and `message`
fields. Read the code to branch:

```aql
def result (do [["a" "b"] Sort.counting end] error [ get code ])
print (result) end
# => bad_input
```

The message says exactly what was wrong:

```aql
def msg (do [[3 -1 2] Sort.radix-lsd end] error [ get message ])
print (msg) end
# => Sort.radix-lsd: needs non-negative Integers (got -1)
```

The two error codes are `bad_input` (a distribution sort got a
non-Integer, a negative where it needs non-negative, or a value range
over 1e8) and `bogo_giveup` (`Sort.bogo` exceeded its shuffle cap; use it
only on tiny inputs). To dispatch on the code, use `case` —
`get code case [bad_input/q "clean the input" "unexpected"]`. In a test,
assert the failure instead:

```aql
import "aql:test"
[["a" "b"] Sort.counting end] Assert.throws end
def e (do [["a" "b"] Sort.counting end])
bad_input/q (e get code) Assert.equal end
```

(Why the module raises coded errors:
[Explanation → Raising errors](explanation.md#raising-coded-errors).)

---

## Run the tests

Five suites ship with the module. Run them with `aql`:

```bash
aql test/sort_unit_test.aql   # example-based unit tests — direct (aql:test)
aql test/sort_unit_spec.aql   # example-based unit tests — declarative spec format
aql test/sort_prop_test.aql   # property tests — direct Test.check-prop form
aql test/sort_prop_spec.aql   # property tests — declarative spec format
aql test/sort_smoke_test.aql  # end-to-end walk-through over every public word
```

The file names follow a consistent convention: `_test.aql` is a direct
suite (assertions or `Test.check-prop` calls written out in code), and
`_spec.aql` is a declarative suite (cases or properties built as data and
handed to a runner). Both the unit and property layers ship in both forms.

The two unit suites express the same example checks two ways:
`sort_unit_test.aql` asserts imperatively with `Test.test` /
`Assert.equal`, while `sort_unit_spec.aql` builds each check as a
`TestSpec` (`Test.spec` / `Test.case`) that `Test.run-spec` dispatches.

The two property suites are likewise split: `sort_prop_spec.aql` builds
each property as a declarative `PropertySpec` (`Test.prop`) and runs it
with `Test.run-property`, while `sort_prop_test.aql` calls the imperative
`Test.check-prop` driver directly, passing `runs`/`seed`/`max-shrinks`
explicitly. The properties cross-check every algorithm against the stable
`Sort.merge` reference and assert the no-mutation and is-sorted invariants.

Each assertion-bearing test file ends by asserting `Test.fail-count` is
`0` and printing `all green`, so a failure makes `aql` exit non-zero —
which is exactly what the CI workflow checks on every push and pull
request.

One more check sits outside this set. `test/divergence/` runs every suite
through all three of aql's execution surfaces — the interpreter, `aql
check` (static type-check), and the byte compiler (`aql --compile`) — and
asserts none errors or disagrees. Run it with:

```bash
test/divergence/run.sh
```

It builds a newer aql (the `--compile` CLI postdates this module's pin)
and prints a per-suite interpreter/check/bytecode matrix. See
[`test/divergence/README.md`](../test/divergence/README.md) for details.
