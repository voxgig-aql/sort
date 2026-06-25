---
name: sort-aql
description: Use when writing or editing AQL code that calls the Sort sorting library — Sort.quick / Sort.merge / Sort.heap / Sort.tim / Sort.counting / Sort.radix-lsd and the other algorithms, the comparators Sort.by-number / Sort.by-string / Sort.natural / Sort.case-insensitive / Sort.reverse / Sort.by-key, or any file that does `import "./sort.aql"`. Provides the exact AQL calling convention (which is not C/Python/JS), the comparator-driven API, verified copy-paste idioms, and fixes for the mistakes agents most often make (foreign call syntax like `xs.sort(cmp)`, missing `end` terminators, forgetting `/r` on a comparator, assuming sorts mutate in place).
---

# Calling the Sort library (AQL)

Every well-known sorting algorithm, over every AQL type, driven by
composable **comparators**. Public surface = the `Sort` namespace. Sorts
return a **new** sorted `List` and never mutate their input. Everything
below is verified against `aql @ c5fbb04`.

## Import

```aql
import "./sort.aql"
```

- Path resolves relative to the **working directory the script runs
  from**, not the importing file. Adjust the relative path accordingly.
- No `end` is needed after `import` on this build (a trailing `end` is
  harmless).
- Do **not** import `aql:string-util` / `aql:math-util` — the library
  does it.

## The one calling rule

AQL has no `f(a, b)` and no `obj.method(a)`. Write:

```
list Sort.verb comparator end
```

List/data first, then the verb, then the comparator (for comparison
sorts), **terminated with `end`** (or wrap the whole call in parens).
Without a terminator the verb swallows the following token.

```aql
[3 1 2] Sort.quick Sort.by-number end             # => [1, 2, 3]
[5 2 8 1] Sort.counting end                        # => [1, 2, 5, 8]  (no comparator)
```

### Passing a comparator

- A namespace comparator → **bare**: `Sort.by-number`.
- Your own comparator word → with **`/r`**: `mycmp/r`.
- The built-in `cmp` → `cmp/r`.

A comparator is a two-argument function returning a negative / zero /
positive `Integer` (first sorts before / equal to / after the second) —
the same contract as `cmp`.

## API

### Comparison sorts — `list Sort.<algo> comparator end → List`
`bubble`, `insertion`, `selection`, `gnome`, `cocktail`, `comb`, `shell`,
`odd-even`, `cycle`, `pancake`, `bitonic`, `quick`, `merge` (stable, the
reference), `heap`, `intro`, `tim` (stable), and `sort` (default = stable
merge).

### Distribution sorts — `list Sort.<algo> end → List` (Integers, ascending, NO comparator)
`counting`, `pigeonhole` (negatives OK), `radix-lsd`, `radix-msd`, `bead`
(**non-negative** only), `bucket`. Bad elements raise `bad_input`.

### Joke sorts — `list Sort.<algo> comparator end → List`
`stooge`, `slow`, and `bogo` (raises `bogo_giveup` past its cap — tiny
inputs only).

### Comparators & combinators
`a b Sort.by-number end`, `Sort.by-string`, `Sort.by-boolean`,
`Sort.by-generic`, `Sort.natural` (alphanumeric: `"file2" < "file10"`),
`Sort.case-insensitive`; `comp Sort.reverse end` (descending) and
`keyfn Sort.by-key end` (order by a derived key). Predicate:
`list Sort.is-sorted comparator end → Boolean`.

Catch errors with `do […] error […]`; read `e get code` in the handler.

## Idioms (verified)

```aql
import "./sort.aql"
print (([5 3 8 1] Sort.quick Sort.by-number end)) end                # => [1, 3, 5, 8]
print ((["pear" "Apple" "fig"] Sort.merge Sort.by-string end)) end   # => ['Apple', 'fig', 'pear']
print (([5 3 8 1] Sort.quick (Sort.by-number Sort.reverse) end)) end # => [8, 5, 3, 1]
```

Natural / alphanumeric order (numbers compare by value, not digit):

```aql
print ((["file10" "file2" "file1"] Sort.merge Sort.natural end)) end # => ['file1', 'file2', 'file10']
```

Custom comparator and sort-by-key:

```aql
def by-len fn [[b:Any a:Any] [Integer] [ (a size) (b size) cmp ]]
print ((["bbb" "a" "cc"] Sort.merge by-len/r end)) end               # => ['a', 'cc', 'bbb']
print ((["bbb" "a" "cc"] Sort.merge (by-len/r Sort.by-key) end)) end # => ['a', 'cc', 'bbb']
```

## Common mistakes

| ✗ Don't | ✓ Do | Why |
|---------|------|-----|
| `Sort.quick([3 1 2], cmp)` / `[3 1 2].sort(cmp)` | `[3 1 2] Sort.quick cmp/r end` | AQL has no call/method syntax. |
| `xs Sort.quick Sort.by-number` (no terminator) | `… end` | The verb swallows the next token. |
| `xs Sort.quick mycmp end` | `xs Sort.quick mycmp/r end` | A bare own-word comparator auto-invokes; `/r` passes it as a value. |
| `xs Sort.quick Sort.by-number/r end` | `xs Sort.quick Sort.by-number end` | Namespace comparators are already values — no `/r`. |
| sort `xs`, then read `xs` as sorted | `def s (xs Sort.quick … end)` | Sorts return a **new** List; the input is unchanged. |
| `[3 -1 2] Sort.radix-lsd end` | `Sort.counting`, or non-negative input | radix/bead need non-negative Integers (`bad_input`). |
| `["a" "b"] Sort.counting end` | `["a" "b"] Sort.merge Sort.by-string end` | distribution sorts are Integer-only. |
| `"label" print (v) print` | `print (v) end`, one per statement | `print` collects forward; chains print out of order. |

If the full repo is available, `AGENTS.md`, `api.json` (machine-readable
signatures), and `docs/reference.md` have the complete guide;
`test/sort_smoke_test.aql` is a runnable example.
