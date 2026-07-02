---
name: sort-aql
description: Use when writing or editing AQL code that calls the Sort sorting library — Sort.quick / Sort.merge / Sort.heap / Sort.tim / Sort.counting / Sort.radix-lsd and the other algorithms, the comparators Sort.by-number / Sort.by-string / Sort.natural / Sort.case-insensitive / Sort.reverse / Sort.by-key, or any file that does `import "./sort.aql"`. Provides the exact AQL calling convention (which is not C/Python/JS), the comparator-driven API, verified copy-paste idioms, and fixes for the mistakes agents most often make (foreign call syntax like `xs.sort(cmp)`, misbinding the argument order — the list is the LAST argument — missing `end` terminators, forgetting `/r` on a comparator, assuming sorts mutate in place).
---

# Calling the Sort library (AQL)

Every well-known sorting algorithm, over every AQL type, driven by
composable **comparators**. Public surface = the `Sort` namespace. Sorts
return a **new** sorted `List` and never mutate their input. Everything
below is verified against `aql @ 7b1a4fb`.

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

AQL has no `f(a, b)` and no `obj.method(a)`. Every `Sort` word takes the
list (the **receiver**) as its **last** parameter, so two orders bind
correctly:

```
Sort.verb comparator list      # forward (canonical): args first, receiver LAST
list Sort.verb comparator      # piping: the receiver flows in from the left
```

Both produce the same result. Prefer the **forward** form — because the
receiver is last, the call is *saturated* by it and needs no `end` (the
closing paren terminates it). The **piping** form needs `end` (or parens)
because the trailing comparator would otherwise swallow the next token.

```aql
Sort.quick Sort.by-number [3 1 2]         # => [1, 2, 3]    ✓ forward (canonical)
[3 1 2] Sort.quick Sort.by-number end     # => [1, 2, 3]    ✓ piping (needs end)
Sort.counting [5 2 8 1]                    # => [1, 2, 5, 8] (no comparator)
```

The **one** order that MISBINDS is receiver-first-all-forward —
`Sort.verb list comparator` — where the list is read as the comparator and
the comparator as the list, raising a `signature_error`:

```aql
Sort.quick [3 1 2] Sort.by-number         # ✗ WRONG — misbinds; do not write this
```

> The API reference below is written in the piping shape
> `list Sort.<algo> comparator end` for readability, but the canonical
> forward equivalent `Sort.<algo> comparator list` is exactly as valid.
> Use either — just never `Sort.<algo> list comparator`.

### Passing a comparator

- A namespace comparator → **bare**: `Sort.by-number`.
- Your own comparator word → with **`/r`**: `mycmp/r`.
- The built-in `cmp` → `cmp/r`.
- Capturing a comparator into a local `def` is still a value hand-off —
  `def numcmp (Sort.by-number/r)` — and pass it on later with `/r` too
  (`Sort.quick numcmp/r nums`), since a bare word there would dispatch.

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

Canonical **forward** form — `Sort.verb  args  receiver` (receiver last):

```aql
import "./sort.aql"
print ((Sort.quick Sort.by-number [5 3 8 1])) end                    # => [1, 3, 5, 8]
print ((Sort.merge Sort.by-string ["pear" "Apple" "fig"])) end       # => ['Apple', 'fig', 'pear']
print ((Sort.quick (Sort.by-number Sort.reverse) [5 3 8 1])) end     # => [8, 5, 3, 1]
```

The **piping** form (receiver first) is equally valid — it just needs an
`end` before the paren closes:

```aql
print (([5 3 8 1] Sort.quick Sort.by-number end)) end                # => [1, 3, 5, 8]
```

Natural / alphanumeric order (numbers compare by value, not digit):

```aql
print ((Sort.merge Sort.natural ["file10" "file2" "file1"])) end     # => ['file1', 'file2', 'file10']
```

Custom comparator (2-arg) and sort-by-key (a 1-arg **key function**):

```aql
def by-len fn [[b:Any a:Any] [Integer] [ (a size) (b size) cmp ]]    # 2-arg comparator
print ((Sort.merge by-len/r ["bbb" "a" "cc"])) end                   # => ['a', 'cc', 'bbb']

def len-of fn [[s:Any] [Integer] [ s size ]]                         # 1-arg key function
print ((Sort.merge (len-of/r Sort.by-key) ["bbb" "a" "cc"])) end     # => ['a', 'cc', 'bbb']
```

## Common mistakes

| ✗ Don't | ✓ Do | Why |
|---------|------|-----|
| `Sort.quick([3 1 2], cmp)` / `[3 1 2].sort(cmp)` | `Sort.quick cmp/r [3 1 2]` (or `[3 1 2] Sort.quick cmp/r end`) | AQL has no call/method syntax. |
| `Sort.quick nums Sort.by-number` (receiver between verb and comparator) | `Sort.quick Sort.by-number nums` (receiver LAST) | Receiver-first-all-forward misbinds: the list is read as the comparator (`signature_error`). |
| `xs Sort.quick Sort.by-number` (piping, no terminator) | add `end`, or use forward `Sort.quick Sort.by-number xs` | In piping the trailing comparator swallows the next token; forward form needs no `end`. |
| `xs Sort.quick mycmp end` | `xs Sort.quick mycmp/r end` | A bare own-word comparator auto-invokes; `/r` passes it as a value. |
| `xs Sort.quick Sort.by-number/r end` | `xs Sort.quick Sort.by-number end` | Namespace comparators are already values — no `/r`. |
| sort `xs`, then read `xs` as sorted | `def s (xs Sort.quick … end)` | Sorts return a **new** List; the input is unchanged. |
| `[3 -1 2] Sort.radix-lsd end` | `Sort.counting`, or non-negative input | radix/bead need non-negative Integers (`bad_input`). |
| `["a" "b"] Sort.counting end` | `["a" "b"] Sort.merge Sort.by-string end` | distribution sorts are Integer-only. |
| `"label" print (v) print` | `print (v) end`, one per statement | `print` collects forward; chains print out of order. |

## Result semantics

- **Sorts return a NEW List** — they never mutate the input. Bind the
  result (`def s (Sort.quick Sort.by-number xs)`). Maps and Lists are
  immutable; for in-place work use a mutable `FlexList` (`flex`).
- **`eq` is identity, `deq` is structural.** `[1 2 3] eq [1 2 3]` is
  `false` (distinct objects); use `deq` when asserting a sorted List
  equals an expected List by value.
- **Integer overflow fails loud.** AQL Integers are fixed-width (signed
  64-bit); arithmetic that overflows the range raises `integer_overflow`
  rather than wrapping — this is intended. The default comparators use
  `cmp`, which never subtracts, so ordering itself is overflow-safe; watch
  overflow only in your own key/arithmetic (`add`, `mul`, …).

If the full repo is available, `AGENTS.md`, `api.json` (machine-readable
signatures), and `docs/reference.md` have the complete guide;
`test/sort_smoke_test.aql` is a runnable example.
