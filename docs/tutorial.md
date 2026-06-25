# Tutorial: your first sort

This is a hands-on lesson. By the end you will have built a small AQL
script that sorts numbers, sorts strings, sorts by a comparator you write
yourself, and sorts a list of filenames into *natural* (alphanumeric)
order. You need no prior knowledge of this library — just a working `aql`
binary (see [How-to → Install and run](how-to.md#install-and-run-aql))
and this repository checked out.

> **AI agents:** for the calling convention and a verified cheat-sheet,
> see [AGENTS.md](../AGENTS.md).

Follow along by typing the script into a file as we grow it. We will
build it up in pieces and run it after each step.

---

## Step 1 — import the module and sort some numbers

Create a file `play.aql` next to `sort.aql` with this content:

```aql
import "./sort.aql"

# Print one value per statement, fully grouped — `print (value) end` —
# and output appears in source order. (Chained `(a) print (b) print`
# pairs print out of order, because print collects a forward argument.)

print (([5 3 8 1 9 2] Sort.quick Sort.by-number end)) end
```

Read that call left to right: the **data comes first** (`[5 3 8 1 9 2]`),
then the verb (`Sort.quick`), then the **comparator** that decides the
order (`Sort.by-number`), and the whole call is terminated with `end`.
This is AQL's universal shape — receiver first, then the word, then any
extra arguments. There is no `sort(list, cmp)` and no `list.sort(cmp)`
here. Run it:

```console
$ aql play.aql
[1, 2, 3, 5, 8, 9]
```

`Sort.by-number` is a *comparator*: a little function that, given two
items, says which comes first. `Sort.quick` is the algorithm — quicksort.
The library ships a whole catalogue of algorithms (merge, heap, tim,
insertion, …); they all take the same shape, so you can swap `Sort.quick`
for `Sort.merge` and get the same answer. The result is a **new** sorted
list — your original `[5 3 8 1 9 2]` is untouched (more on that in
Step 5).

---

## Step 2 — sort strings instead

The only thing that changes when you sort a different kind of data is the
comparator. For strings, reach for `Sort.by-string`, which orders them
lexicographically (by character code). Append below the first line:

```aql
print ((["pear" "Apple" "fig"] Sort.merge Sort.by-string end)) end
```

```console
$ aql play.aql
[1, 2, 3, 5, 8, 9]
["Apple", "fig", "pear"]
```

`"Apple"` sorts first because an uppercase `A` (code point 65) comes
before the lowercase letters (`f`, `p` are 102, 112). That is plain
lexicographic order — we will fix the case-sensitivity in a moment. Note
the `end` after every call: AQL words look ahead for arguments, and `end`
marks where the call stops. Forget it and the next token gets swallowed
as an argument.

---

## Step 3 — write your own comparator

The built-in comparators cover the common orders, but the real power is
that *you* can supply the ordering. A comparator is a two-argument
function returning a negative / zero / positive Integer when the first
item should sort before / equal to / after the second — exactly the
contract of the built-in `cmp`. Let's order strings by **length** instead
of alphabetically. Add:

```aql
def by-length fn [
  [b:Any a:Any] [Integer] [ (a size) (b size) cmp ]
]

print ((["bbb" "a" "cc"] Sort.merge by-length/r end)) end
```

```console
$ aql play.aql
...
["a", "cc", "bbb"]
```

Two things to notice. First, the body is written in terms of `a` (the
earlier item) and `b` (the later one): we compare their sizes with the
native `cmp`, so a shorter string sorts first. Second — and this is the
one rule that trips people up — we pass the comparator as `by-length/r`,
**with a `/r` suffix**. A bare word would *call* `by-length` on the spot;
`/r` hands it over as a value for the sort to call later. (Comparators
from the `Sort` namespace, like `Sort.by-number`, are already values, so
they need no `/r`.)

---

## Step 4 — natural (alphanumeric) order

Here is the headline utility. Imagine sorting a list of filenames:

```aql
print ((["file10" "file2" "file1"] Sort.merge Sort.by-string end)) end
```

```console
$ aql play.aql
...
["file1", "file10", "file2"]
```

That is almost certainly *not* what you want: `"file10"` lands before
`"file2"` because, character by character, `"1"` comes before `"2"`. Swap
in `Sort.natural`, which compares embedded runs of digits by their
**numeric value**:

```aql
print ((["file10" "file2" "file1"] Sort.merge Sort.natural end)) end
```

```console
$ aql play.aql
...
["file1", "file2", "file10"]
```

Now `file2` precedes `file10`, because `2 < 10` as numbers. This works
for digit runs anywhere in the string — `"x9"` sorts before `"x10"` too.

---

## Step 5 — sorts return a new list

One last idea that shapes how you use the library: a sort never modifies
its input. It returns a brand-new sorted list and leaves the original
alone. See it directly:

```aql
def original [3 1 2]
def sorted (original Sort.quick Sort.by-number end)
print (original) end
print (sorted) end
```

```console
$ aql play.aql
...
[3, 1, 2]
[1, 2, 3]
```

`original` is still `[3 1 2]`; `sorted` is the ordered copy. So always
*bind the result* of a sort (`def sorted (… )`) — there is no in-place
variant that mutates the list you passed in. Why the library is built
this way is covered in
[Explanation → Why sorts return new lists](explanation.md#why-sorts-return-new-lists).

---

## What you've learned

- A sort is written **data first**: `list Sort.<algo> comparator end`.
- The **comparator** decides the order: `Sort.by-number`,
  `Sort.by-string`, `Sort.natural`, and friends — or one you write.
- Pass a `Sort.*` comparator bare; pass your own comparator word (or the
  built-in `cmp`) with a **`/r`** suffix.
- All the comparison algorithms (`quick`, `merge`, `heap`, …) share one
  shape, so they are interchangeable.
- Sorts return a **new** list; the input is never mutated.

## Where to go next

- Solve specific problems with the [How-to guides](how-to.md) — custom
  orders, descending, by-key, distribution sorts, error handling, running
  the tests.
- Look up every algorithm and comparator in the [Reference](reference.md).
- Understand the comparator-driven design in the
  [Explanation](explanation.md).
