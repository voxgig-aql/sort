# Reference

Technical description of the `sort` module's public surface. This page is
information-oriented: it states what each word is, its call shape, what it
returns, and — for the algorithms — stability, complexity, and
constraints. For *why* the library is built this way, see
[Explanation](explanation.md); for goal-directed recipes, the
[How-to guides](how-to.md).

> **AI agents:** [AGENTS.md](../AGENTS.md) condenses the calling
> convention, idioms, and common mistakes for machine use.

The module exports a single namespace, `Sort`. Import it with:

```aql
import "./sort.aql"
```

(No `end` is required after `import` on the pinned build; a trailing `end`
is harmless.) A consuming script does **not** need to import
`aql:string-util` or `aql:math-util` itself — `sort.aql` imports them
internally.

---

## Calling convention

Every operation is a forward-dispatched word and must be terminated with
`end` (or wrapped in parentheses) at the call site, e.g.
`xs Sort.quick Sort.by-number end` or `(xs Sort.quick Sort.by-number)`.
Without a terminator the word collects the following token as an argument.
This is general AQL forward-precedence behaviour, not specific to this
module.

The shape is **data first**, then the verb, then the comparator (for the
comparison and joke sorts; the distribution sorts take none):

```
list Sort.<algo> comparator end   →   List (new, sorted; input unchanged)
list Sort.<algo>            end    →   List       (distribution sorts)
```

### Passing a comparator

| You want to use… | Write it as | Why |
|---|---|---|
| a comparator from this namespace | `Sort.by-number` (bare) | already a value in the namespace map |
| your own comparator word | `mycmp/r` | `/r` hands the word over as a value instead of invoking it |
| the built-in `cmp` | `cmp/r` | same — `/r` defers the call |

### No mutation

Every algorithm returns a **new** sorted `List`; the input `List` is never
modified. This is the opposite of an in-place library. Always bind the
result (`def s (xs Sort.quick … end)`); the original is unchanged.

---

## Comparators

A comparator is a two-argument function value with signature
`[b:T a:T] [Integer]`: given two items it returns a negative / zero /
positive Integer when the first sorts before / equal to / after the
second. Only the sign matters — the same contract as the built-in `cmp`.
The defaults defer to `cmp` (a three-way compare that never subtracts, so
there is no integer-overflow risk).

| Call | Returns | Order |
|------|---------|-------|
| `a b Sort.by-number end` | `Integer` | ascending numeric (Integer or Float) |
| `a b Sort.by-string end` | `Integer` | lexicographic (code-point) |
| `a b Sort.by-boolean end` | `Integer` | `false` before `true` |
| `a b Sort.by-generic end` | `Integer` | polymorphic via `cmp` |
| `a b Sort.natural end` | `Integer` | alphanumeric: embedded digit runs compare numerically, so `"file2" < "file10"` |
| `a b Sort.case-insensitive end` | `Integer` | case-folded lexicographic |

### Combinators

Each returns a **new** comparator (a closure over its argument), so they
compose — e.g. `(length-of/r Sort.by-key) Sort.reverse`.

| Call | Args | Returns | Effect |
|------|------|---------|--------|
| `comp Sort.reverse end` | `comp:Comparator` | `Comparator` | reverses `comp` (descending) |
| `keyfn Sort.by-key end` | `keyfn:Function` | `Comparator` | orders items by the key `keyfn` extracts, compared with `cmp` |

```aql
print (([3 1 2] Sort.quick (Sort.by-number Sort.reverse) end)) end   # => [3, 2, 1]
def len-of fn [[s:Any] [Integer] [ s size ]]
print ((["bbb" "a" "cc"] Sort.merge (len-of/r Sort.by-key) end)) end # => ["a", "cc", "bbb"]
```

---

## Comparison sorts

`list Sort.<algo> comparator end → List`. All produce the same ordering
for a given comparator; they differ in stability and cost. *Stable* means
equal elements keep their input order. Complexities are average-case
unless noted; `n` is the list length.

| Algorithm | Stable | Time | Space | Notes |
|-----------|--------|------|-------|-------|
| `bubble`    | yes | O(n²) | O(n) | adjacent-swap passes |
| `insertion` | yes | O(n²), O(n) on nearly-sorted | O(n) | grows a sorted prefix |
| `selection` | no  | O(n²) | O(n) | selects each minimum in turn |
| `gnome`     | yes | O(n²) | O(n) | single back-and-forth cursor |
| `cocktail`  | yes | O(n²) | O(n) | bidirectional bubble |
| `comb`      | no  | O(n²) worst, ~O(n log n) typical | O(n) | shrinking-gap bubble |
| `shell`     | no  | O(n²) worst (halving gaps) | O(n) | gapped insertion |
| `odd-even`  | yes | O(n²) | O(n) | brick / phase pairs |
| `cycle`     | no  | O(n²) | O(n) | minimal writes |
| `pancake`   | no  | O(n²) | O(n) | prefix-flip the maximum into place |
| `bitonic`   | no  | O(n log²n) | O(n) | sorting network, generalised to **any** length |
| `quick`     | no  | O(n log n), O(n²) worst | O(n) | Lomuto partition on the last element |
| `merge`     | **yes** | O(n log n) | O(n) | **the reference** other sorts are checked against |
| `heap`      | no  | O(n log n) | O(n) | binary max-heap |
| `intro`     | no  | O(n log n) **worst case** | O(n) | quicksort with a heapsort fallback |
| `tim`       | **yes** | O(n log n), O(n) on nearly-sorted | O(n) | natural-run detection + stable merge |
| `sort`      | **yes** | O(n log n) | O(n) | recommended default (currently stable merge) |

The space column is O(n) throughout because each algorithm copies the
input into a fresh working Array (the input is never mutated) even when
the underlying ordering is "in place" on that copy.

```aql
print (([5 3 8 1] Sort.quick Sort.by-number end)) end   # => [1, 3, 5, 8]
print (([5 3 8 1] Sort.sort  Sort.by-number end)) end   # => [1, 3, 5, 8]
```

---

## Distribution sorts

`list Sort.<algo> end → List`. These take **no comparator** and order
**Integers ascending** by counting or bucketing rather than comparing.
`k` is the value range (`max − min + 1`); `d` is the number of digits in
the maximum.

| Algorithm | Time | Space | Constraint |
|-----------|------|-------|------------|
| `counting`   | O(n + k) | O(n + k) | Integers; negatives OK |
| `pigeonhole` | O(n + k) | O(n + k) | Integers; negatives OK |
| `radix-lsd`  | O(d·(n + 10)) | O(n) | **non-negative** Integers (base 10), stable |
| `radix-msd`  | O(d·(n + 10)) | O(n) | **non-negative** Integers (base 10), recursive |
| `bucket`     | O(n + k) average | O(n) | Integers; value-range buckets, insertion-sorted then gathered |
| `bead`       | O(n·max) | O(n·max) | **non-negative** Integers (gravity sort) |

`counting` and `pigeonhole` raise `bad_input` on a non-Integer element or
a value range over 1e8. The radix family and `bead` raise `bad_input` on a
non-Integer or a **negative** element.

```aql
print (([170 45 75 90 2 802] Sort.radix-lsd end)) end   # => [2, 45, 75, 90, 170, 802]
print (([5 -2 8 -1 0] Sort.counting end)) end           # => [-2, -1, 0, 5, 8]
```

---

## Joke / educational sorts

`list Sort.<algo> comparator end → List`. Correct, but deliberately
inefficient — for demonstration, not production.

| Algorithm | Time | Notes |
|-----------|------|-------|
| `stooge` | O(n^2.71) | recursive; sorts thirds in a fixed pattern |
| `slow`   | superpolynomial | "multiply and surrender"; recursive |
| `bogo`   | unbounded (capped) | shuffle-until-sorted with a deterministic LCG and a hard cap; raises `bogo_giveup` past the cap — use only on tiny inputs |

```aql
print (([2 1] Sort.bogo Sort.by-number end)) end   # => [1, 2]
```

---

## Predicate

### `Sort.is-sorted`

Test whether a list is already ordered under a comparator.

| | |
|--|--|
| **Call**    | `list Sort.is-sorted comparator end` |
| **Stack in**| a `List`, then a comparator |
| **Returns** | `Boolean` — `true` iff `list` is ordered under the comparator |

```aql
print (([1 2 3] Sort.is-sorted Sort.by-number end)) end   # => true
print ((["c" "a" "b"] Sort.is-sorted Sort.by-string end)) end   # => false
```

---

## Errors at a glance

All failures raise coded errors; catch with `do […] error […]` and read
`e get code` / `e get message` (dispatch on several codes with `case`).

| Code | Raised by | Situation |
|------|-----------|-----------|
| `bad_input` | the distribution sorts | a non-Integer element; a negative element to `radix-lsd`/`radix-msd`/`bead`; or a value range over 1e8 for `counting`/`pigeonhole` |
| `bogo_giveup` | `bogo` | shuffle cap exceeded without reaching sorted order |

A missing `end` after a `Sort.*` call is not a module error but a general
AQL dispatch problem — the word collects the following token (add `end` or
parens).
