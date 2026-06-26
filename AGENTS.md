# AGENTS.md — using the `Sort` library

Guidance for an AI coding agent calling this sorting library from an AQL
project. Every code block below is verified to run against `aql-lang/aql`
@ `7b1a4fb`. If you read nothing else, read
[The one calling rule](#the-one-calling-rule) and
[Common mistakes](#common-mistakes).

## What it is

Every well-known sorting algorithm, over every AQL type, driven by
composable **comparators**. The public surface is the single `Sort`
namespace. Sorts return a **new** sorted `List` and never mutate their
input.

- **Comparison sorts** (take a comparator): `bubble`, `insertion`,
  `selection`, `gnome`, `cocktail`, `comb`, `shell`, `odd-even`, `cycle`,
  `pancake`, `bitonic`, `quick`, `merge`, `heap`, `intro`, `tim`, and the
  default `sort`.
- **Distribution sorts** (no comparator; Integers ascending): `counting`,
  `pigeonhole`, `radix-lsd`, `radix-msd`, `bucket`, `bead`.
- **Joke / educational sorts** (take a comparator): `bogo`, `stooge`,
  `slow`.
- **Comparators**: `by-number`, `by-string`, `by-boolean`, `by-generic`,
  `natural` (alphanumeric), `case-insensitive`, plus the combinators
  `reverse` and `by-key`.
- **Predicate**: `is-sorted`.

## Import

```aql
import "./sort.aql"
```

- The path is resolved **relative to the working directory the script is
  run from**, not the importing file. Run scripts from where that path is
  valid (adjust otherwise).
- No `end` is needed after `import` on this build; a trailing `end` is
  harmless.
- Do **not** import `aql:string-util` or `aql:math-util` yourself —
  `sort.aql` imports its own dependencies.

## The one calling rule

AQL is not C/Python/JS. There is no `f(a, b)` and no `obj.method(a)`.
A call is written:

```
data Sort.verb comparator end
```

— the **list/data comes first**, then the verb, then the comparator (for
comparison sorts), terminated with `end` (or wrapped in parens). Without a
terminator the verb swallows whatever token follows it.

```aql
[3 1 2] Sort.quick Sort.by-number end             # => [1 2 3]
["file2" "file10"] Sort.merge Sort.natural end    # => [file2 file10]
[5 2 8 1] Sort.counting end                        # => [1 2 5 8]  (no comparator)
```

### Passing a comparator

| You want to use… | Write it as | Why |
|---|---|---|
| a comparator from this namespace | `Sort.by-number` (bare) | it is already a value in the namespace map |
| your own comparator word | `mycmp/r` | `/r` hands the word over as a value instead of invoking it |
| the built-in `cmp` | `cmp/r` | same — `/r` defers the call |

```aql
def by-len fn [[b:Any a:Any] [Integer] [ (a size) (b size) cmp ]]
["bbb" "a" "cc"] Sort.merge by-len/r end           # => [a cc bbb]
[3 1 2]           Sort.heap  cmp/r   end            # => [1 2 3]
```

## A comparator's contract

A comparator is a two-argument function value. Given two items it returns
an **Integer**: negative if the first sorts before the second, zero if
they are equivalent, positive if after. Only the sign matters — the same
contract as the built-in `cmp` and as C's `qsort`. Write the body in terms
of `a` (the earlier item) and `b` (the later one):

```aql
def by-second fn [
  [b:Any a:Any] [Integer] [ (a get 1) (b get 1) cmp ]   # order pairs by their 2nd element
]
```

## API reference (exact call shapes)

### Comparison sorts — `list Sort.<algo> comparator end → List`

| Algorithm | Notes |
|-----------|-------|
| `merge` | **Stable**; the reference the others are checked against. |
| `tim` | **Stable**; natural-run detection + merge. |
| `insertion`, `bubble`, `cocktail`, `gnome` | Stable, simple, O(n²). |
| `selection`, `comb`, `shell`, `odd-even`, `cycle`, `pancake` | In-place family, O(n²)/sub-quadratic. |
| `quick` | Lomuto partition, O(n log n) average. |
| `heap` | O(n log n), in-place heap. |
| `intro` | Quicksort with a heapsort fallback (O(n log n) worst case). |
| `bitonic` | Sorting network, generalised to **any** length. |
| `sort` | The recommended default (currently stable merge sort). |

### Distribution sorts — `list Sort.<algo> end → List` (Integers, ascending, no comparator)

| Algorithm | Constraint |
|-----------|------------|
| `counting`, `pigeonhole` | Integers (negatives OK); raise `bad_input` on non-Integers or a value range > 1e8. |
| `radix-lsd`, `radix-msd` | **Non-negative** Integers (base 10). |
| `bucket` | Integers. |
| `bead` | **Non-negative** Integers. |

### Joke sorts — `list Sort.<algo> comparator end → List`

`stooge`, `slow` (recursive, very slow), and `bogo` (shuffle-until-sorted;
raises `bogo_giveup` past its cap — use only on tiny inputs).

### Comparators & combinators

| Call | Returns | Notes |
|------|---------|-------|
| `a b Sort.by-number end` | `Integer` | ascending numeric (Integer/Float) |
| `a b Sort.by-string end` | `Integer` | lexicographic |
| `a b Sort.by-boolean end` | `Integer` | `false` before `true` |
| `a b Sort.by-generic end` | `Integer` | polymorphic via `cmp` |
| `a b Sort.natural end` | `Integer` | alphanumeric: `"file2" < "file10"` |
| `a b Sort.case-insensitive end` | `Integer` | case-folded strings |
| `comp Sort.reverse end` | comparator | reverses `comp` (descending) |
| `keyfn Sort.by-key end` | comparator | order by `keyfn`'s key (compared with `cmp`) |

### Predicate

`list Sort.is-sorted comparator end → Boolean`.

## Copy-paste idioms (all verified)

Sort numbers, strings, and a custom order:

```aql
import "./sort.aql"
print (([5 3 8 1] Sort.quick Sort.by-number end)) end                # => [1 3 5 8]
print ((["pear" "Apple" "fig"] Sort.merge Sort.by-string end)) end   # => [Apple fig pear]
print (([5 3 8 1] Sort.quick (Sort.by-number Sort.reverse) end)) end # => [8 5 3 1]
```

Natural / alphanumeric ordering (the headline utility — numbers that
appear as prefixes or suffixes sort by value, not by digit):

```aql
print ((["file10" "file2" "file1"] Sort.merge Sort.natural end)) end # => [file1 file2 file10]
```

Sort by a derived key (here, string length):

```aql
def by-len fn [[s:Any] [Integer] [ s size ]]
print ((["bbb" "a" "cc"] Sort.merge (by-len/r Sort.by-key) end)) end  # => [a cc bbb]
```

Distribution sort over Integers (no comparator):

```aql
print (([170 45 75 90 2 802 24 66] Sort.radix-lsd end)) end          # => [2 24 45 66 75 90 170 802]
```

Check an ordering, and trap a distribution sort's input error:

```aql
print (([1 2 3] Sort.is-sorted Sort.by-number end)) end              # => true
def result (do [["a" "b"] Sort.counting end] error [ get code ])     # => bad_input
```

## Common mistakes

| ✗ Don't write | ✓ Write | Why |
|---------------|---------|-----|
| `Sort.quick([3 1 2], cmp)` | `[3 1 2] Sort.quick cmp/r end` | No `f(a,b)` syntax in AQL. |
| `[3 1 2].sort(cmp)` | `[3 1 2] Sort.quick cmp/r end` | No method-call syntax. |
| `xs Sort.quick Sort.by-number` (no terminator) | `xs Sort.quick Sort.by-number end` | The verb swallows the next token without `end`/parens. |
| `xs Sort.quick mycmp end` | `xs Sort.quick mycmp/r end` | A bare own-word comparator auto-invokes; `/r` passes it as a value. |
| `xs Sort.quick Sort.by-number/r end` | `xs Sort.quick Sort.by-number end` | Namespace comparators are already values — no `/r`. |
| treat a sort as in-place (sort `xs`, then read `xs`) | bind the result: `def s (xs Sort.quick … end)` | Sorts return a **new** List; the input is unchanged. |
| `[3 -1 2] Sort.radix-lsd end` | use `Sort.counting`, or non-negative input | radix/bead need non-negative Integers (else `bad_input`). |
| `["a" "b"] Sort.counting end` | `["a" "b"] Sort.merge Sort.by-string end` | distribution sorts are Integer-only. |
| `xs Sort.bogo cmp/r end` on a big list | only tiny lists, or use `Sort.quick` | bogosort raises `bogo_giveup` past its cap. |

A note on `print` while debugging: `print` collects a forward argument,
so write `print (value) end` — one value per statement — and output
appears in source order.

## Where to look next

- `docs/reference.md` — full per-word reference, stability, complexity.
- `api.json` — the same API as a machine-readable manifest.
- `docs/how-to.md` — task recipes (custom orders, natural sort, by-key).
- `docs/tutorial.md` — a hands-on first sort.
- `docs/explanation.md` — why the comparator-driven design, and the AQL
  idioms it rests on.
- `test/sort_smoke_test.aql` — a complete, runnable worked example.
