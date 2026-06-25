# Explanation

Understanding-oriented discussion of how this sorting library works and
why it is built the way it is. Read this when you want the *why*; for the
*what*, see the [Reference](reference.md), and for *how to get a job
done*, the [How-to guides](how-to.md).

---

## What the library is for

It is a catalogue of sorting algorithms — every well-known comparison
sort, the main distribution sorts, and a few joke sorts — over every AQL
type, driven by a single small abstraction: the **comparator**. You pick
an algorithm and an ordering, write them in AQL's data-first shape, and
get back a new sorted list:

```
list Sort.<algo> comparator end   →   a new sorted List
```

The design goal is that the *ordering* and the *algorithm* are
independent. Any comparator works with any comparison algorithm, and you
swap one without touching the other. The rest of this page explains why
that boundary is a comparator, why the sorts hand back new lists instead
of mutating in place, and the AQL idioms that make both work.

---

## Why the design is comparator-driven

A sort has to answer exactly one question about your data, over and over:
*given two items, which comes first?* Everything else — how items are
moved, how many passes are made, the recursion structure — belongs to the
algorithm and is the same whatever you are sorting. So the library factors
that one question out into a value you supply: the comparator.

The payoff is a small surface that covers a large space. There is no
`sort-numbers`, `sort-strings-descending`, `sort-by-length` family of
words; there is one `Sort.quick` (and `Sort.merge`, `Sort.heap`, …) that
takes whatever ordering you hand it. Orderings compose, too: `Sort.reverse`
turns any comparator into its descending counterpart, and `Sort.by-key`
turns a "how do I extract the sort key" function into a full comparator.
You build the order you need from small pieces rather than reaching for a
bespoke algorithm.

This is the same separation C's `qsort` makes with its comparison
callback, Python's `key=`/`cmp` parameters, and the JS `Array.sort`
comparator — a well-worn boundary. What is particular to AQL is *how* a
comparator is represented and passed, which the next sections cover.

### What a comparator is

A comparator is a two-argument function value. Given two items it returns
an **Integer** whose **sign** is the answer: negative if the first item
sorts before the second, zero if they are equivalent, positive if after.
Only the sign matters — magnitude is ignored — so the contract is exactly
that of the built-in `cmp`.

```aql
def by-length fn [
  [b:Any a:Any] [Integer] [ (a size) (b size) cmp ]
]
```

Two conventions are worth internalising. First, the body is written in
terms of `a` (the *earlier* item) and `b` (the *later* one), so "`a`
before `b` ⇒ negative" reads naturally; AQL's rule that the first
signature parameter is the top of the stack is what makes `a` the earlier
item when a sort invokes `xi xj comp`. Second, the built-in comparators
defer to `cmp` rather than computing `a - b`. A three-way `cmp` never
subtracts, so there is no risk of integer overflow flipping a comparison —
a classic bug in hand-rolled numeric comparators.

---

## Why sorts return new lists

Every algorithm copies its input into a fresh working Array, sorts the
copy, and returns it as a new List. The input list is never touched. This
is the opposite of a traditional in-place sort, and it is a deliberate
choice:

- **Values stay values.** A function that quietly rewrites its argument is
  a source of action-at-a-distance bugs. Returning a new list keeps a sort
  a pure mapping from input to output — easy to reason about, safe to call
  on a list someone else still holds.
- **It matches how the library is tested.** Every algorithm is
  cross-checked against the stable `Sort.merge` reference and asserted not
  to mutate its input. A non-mutation contract is only meaningful if it
  holds uniformly, so all sorts honour it.
- **The cost is bounded and predictable.** The copy is O(n) space, which
  the algorithms would often need for scratch buffers anyway (merge sort's
  merge buffer, the distribution sorts' count arrays).

The practical consequence for callers is the one rule from the
[Tutorial](tutorial.md#step-5--sorts-return-a-new-list): always **bind the
result** (`def sorted (xs Sort.quick … end)`). Reading the original
variable after "sorting" it gives you the original, unsorted list, because
nothing wrote to it.

---

## Why distribution sorts need no comparator

The distribution sorts — `counting`, `pigeonhole`, `radix-lsd`,
`radix-msd`, `bucket`, `bead` — do not take a comparator at all. They do
not compare items against each other; they use each item's **value** as an
index, scattering items into counts or buckets and reading them back in
order. That is how they break the O(n log n) comparison-sort lower bound:
they exploit knowledge a comparator deliberately hides, namely that the
keys are integers in a known range.

The flip side is that this only works for integers (and, for radix and
bead, non-negative ones), so these words validate their input and raise
`bad_input` rather than silently misbehaving. The comparator-driven sorts
and the distribution sorts are thus two answers to two different
situations — arbitrary orderings of arbitrary data versus integer keys —
and the library ships both.

---

## The AQL idioms it rests on

The comparator abstraction is clean in principle, but making it work in
AQL leans on a few language facts worth understanding.

### Postfix, terminated calls

AQL is not C/Python/JS: there is no `sort(list, cmp)` and no
`list.sort(cmp)`. A call is **data first, verb next, arguments after**,
terminated with `end` (or wrapped in parens):

```aql
list Sort.quick Sort.by-number end
```

Words dispatch forward — they look ahead and collect arguments — so the
terminator is load-bearing. Drop the `end` and `Sort.quick` swallows
whatever token follows it as if it were the comparator, giving a wrong
result or a dispatch error. The `(… )` parentheses count as a terminator,
which is why `(xs Sort.quick Sort.by-number)` works too.

### Function values and `/r`

A comparator has to be passed *as a value* — handed to the sort to call
later — not invoked at the call site. AQL's default is to invoke: a bare
word runs. The `/r` suffix is what defers it, parking the word as a value
instead of calling it. So your own comparator and the built-in `cmp` are
passed `mycmp/r`, `cmp/r`. The comparators in the `Sort` namespace
(`Sort.by-number`, …) are *already* values in the namespace map, so they
are passed bare — adding `/r` to them is the common mistake in the other
direction.

### The single-module requirement

A comparator is a function value, and when a sort invokes it, AQL resolves
the comparator's free words — any helper it calls — in **the module that
runs it**. The library's `Sort.natural`, for instance, calls a private
digit-run scanner; that scanner has to be visible where `natural` actually
executes. This is why the comparators and the algorithms live in the same
single module: a comparator's helpers must resolve in the running module,
so the library keeps them together rather than splitting orderings and
algorithms across files. (For your own comparators the same fact is
benign: define the comparator and any helper it uses in the script that
runs the sort, and they resolve.)

### Box-threading comparators through recursion

The divide-and-conquer sorts (`quick`, `merge`, `heap`, `intro`,
`bitonic`, `tim`, and the recursive joke sorts) recurse, and each
recursive call needs the comparator. AQL's handling of a function
*parameter* parked with `/r` is one-shot, which does not survive being
threaded down a recursion. The library sidesteps this by wrapping the
comparator in a one-cell Array — a "box" — built once at the top
(`make Array [comp/r]`) and passed down as a plain Array. Each recursive
frame reads the comparator back out with `def cmpf (box get 0)` and
invokes it as `xi xj cmpf`. Passing a plain Array sidesteps the one-shot
parameter restriction and keeps the static checker happy, so the
comparator stays callable all the way down. This is an implementation
detail — callers never see the box — but it explains a recurring shape in
the source.

### Bounded loops instead of `while`

AQL offers no `while`, so the data-dependent loops (gnome's cursor walk,
comb's gap shrink, bogo's shuffle, …) are written as bounded `iota` loops
with an explicit state cell, where the bound is a proven worst-case step
count for that algorithm. The loop always reaches the sorted state and
then idles for the remaining iterations. This is why, for example, `bogo`
has a hard cap and raises `bogo_giveup` rather than looping forever — there
is no unbounded loop to run.

---

## Design choices specific to this library

### `Sort.merge` as the reference

Merge sort is the stable, predictable O(n log n) implementation, and the
test suite treats it as ground truth: every other algorithm is checked to
produce the same ordering as `Sort.merge` on the same input. `Sort.sort`,
the recommended default, is currently merge sort for exactly this reason —
it is the one whose correctness the rest of the library is measured
against.

### Stability where it is claimed

`merge`, `tim`, and the simple adjacent-swap sorts (`insertion`, `bubble`,
`cocktail`, `gnome`, `odd-even`) preserve the input order of equal
elements; the [Reference](reference.md#comparison-sorts) marks which.
Stability matters when you sort by one key and want ties broken by a
previous ordering — sort by the secondary key first with a stable sort,
then by the primary. The default `Sort.sort` is stable so this composition
just works.

### Raising coded errors

The distribution sorts validate their input and `bogo` enforces its cap by
`raise`-ing coded errors: `bad_input` for a non-Integer / negative /
out-of-range element, `bogo_giveup` for an exhausted shuffle budget.
Handlers catch them with `do […] error […]` and read `code` / `message`
off the Error value. Coded errors let a caller distinguish "you gave me the
wrong kind of data" from a bug, and dispatch on the code with `case`.

---

## Further reading

- [Tutorial](tutorial.md) — sort your first list step by step.
- [How-to guides](how-to.md) — task-focused recipes.
- [Reference](reference.md) — every algorithm and comparator, exactly.
