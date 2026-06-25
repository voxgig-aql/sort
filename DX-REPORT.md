# Developer-experience report — building the `Sort` library in AQL

A field report from converting this repository into the `Sort`
sorting-algorithms library: 25 algorithms and a set of comparators, built
and verified against **`aql-lang/aql @ 12a44e0`** (the pinned commit; see
`api.json`). Every snippet below was run against that build; the observed
output is shown inline.

The goal of this document is to save the next person time, and to give the
`aql` maintainers a prioritized list of sharp edges. It is deliberately
balanced — [§9](#9-what-worked-well) covers what made the build *pleasant*,
which was a lot.

## Update (DX-driven aql fixes)

A later aql build acted on some of the issues below, so the library was
migrated to match it. The accessor family was split: `get`/`getr` now
**evaluate** their key, so a bare literal field name after `get` is an
`undefined_word` error by design — literal-field reads move to the new
`.field` / `!.field` sugar (e.g. `e get code` → `e.code`), or, where the
value is on the stack with no receiver, to the quoted-atom key form
`get field/q`. The only such sites here were the two error-code reads in
`test/sort_unit_test.aql` (`e get code` → `e.code`). Separately, the
`comp/r` frame over-pop bug behind the Array-**box** comparator-threading
workaround ([§1.2](#12-the-def-cf-compr-workaround-trips-the-static-checker))
is fixed, so every divide-and-conquer sort now threads the comparator
**directly** as its `comp:Function` parameter — invoked bare (`xi xj comp`)
and forwarded with `comp/r` — and the recursive `radix-msd` `no_signature`
false positive ([§6](#6-tooling--the-static-checker-aql-check)) is gone, so
`aql check sort.aql` is now **0 errors**. (Note: the `def cf (comp/r)`
local form of [§1.2](#12-the-def-cf-compr-workaround-trips-the-static-checker)
still trips the checker's `undefined_word` false positive, so the box
collapses to the parameter itself rather than to a `cf` local.) These
changes require an aql build carrying those fixes; on the original pinned
build they will not run/check clean.

## Severity legend

- 🔴 **Silent wrong result** — code runs, returns the wrong value, no error.
- 🟠 **Hard error / forced a workaround** — fails loudly; shaped the design.
- 🟡 **Sharp edge** — surprising, but easy to live with once known.

The single biggest theme: **first-class functions are load-bearing for a
comparator-driven library, and they are the least-polished corner of the
language** ([§1](#1-first-class-functions--comparators)). The second:
**collections silently change element identity** in two different ways
([§2](#2-collections--types)).

---

## 1. First-class functions & comparators

A comparator is a two-argument function value threaded into every sort. The
whole library lives or dies on passing functions around, and this is where
most of the time went.

### 1.1 🟠 Parking a Function *parameter* with `/r` is one-shot

`word/r` defers a word as a value. On a **parameter**, the second `/r` in
the same scope fails:

```aql
def mycmp fn [[b:Integer a:Integer] [Integer] [ (a cmp b) ]]
def use1  fn [[comp:Function x:Integer y:Integer] [Integer] [ (x y comp) ]]
def two   fn [[comp:Function a:Integer b:Integer] [Integer] [
  def r1 (a b comp/r use1)
  def r2 (b a comp/r use1)   # <-- second /r on the same param
  r1 add r2
]]
print ((3 7 mycmp/r two)) end
# => error: [aql/undefined_word]: undefined word: comp
```

**Cause (observed):** parking a param appears to consume it from the scope;
a *bound local* does not have this problem. **Workaround:** bind once,
re-reference freely — `def cf (comp/r)` then `cf/r` as many times as needed.
This is the first half of the box pattern below.

### 1.2 🟠 The `def cf (comp/r)` workaround trips the static checker

The bind-once fix runs correctly but `aql check` rejects it:

```aql
def go fn [[comp:Function n:Integer] [Integer] [
  def cf (comp/r)
  def _ (iota n each [var [[i] def r (i i cf/r apply) 0]])
  5 5 cf/r apply
]]
# interpreter: runs fine
# aql check:   4 errors — "undefined_word: cf"
```

Threaded through a dozen recursive sort helpers, that was **89 check
errors** in `sort.aql`, all the same false positive.

**Workaround — the "box" pattern.** Store the comparator in a one-cell
`Array`, forward the *box* (a plain value, no `/r`), and read it back to
invoke:

```aql
def go fn [[comp:Function n:Integer] [Integer] [
  def box (make Array [comp/r])   # park once, into an Array cell
  def cf  (box get 0)             # read back the function value
  def _ (iota n each [var [[i] def r (i i cf) 0]])
  5 5 cf                           # invoke bare
]]
# interpreter: runs fine
# aql check:   0 errors
```

Both forms return the same (correct) result; only the box form is
check-clean. This is the pattern every divide-and-conquer sort uses — see
`sort.aql:306-310` (`quick-go`, `merge-go`, `heap-sort`, `bitonic`, `intro`,
`stooge`, `slow`, `tim`).

**Design impact:** the entire comparator-threading layer was rewritten from
`def cf (comp/r)` to the Array box purely to satisfy the checker.

### 1.3 🟠 A recursive helper reached *through a Function param* fails to resolve

A comparator invoked via a `Function` parameter may call **non-recursive**
helpers, but if a helper it reaches **recurses**, the self-call does not
resolve:

```aql
def dbl  fn [[n:Integer] [Integer] [ n mul 2 ]]                            # non-recursive
def deep fn [[n:Integer] [Integer] [ if (n lte 0) [0] [ (n sub 1) deep ] ]] # recursive
def hcmp fn [[b:Any a:Any] [Integer] [ def s (a dbl)  (s b cmp) ]]
def rcmp fn [[b:Any a:Any] [Integer] [ def s (a deep) (s b cmp) ]]
def run  fn [[comp:Function y:Any x:Any] [Any] [ (x y comp/r apply) ]]
print ((typeof (do [ 3 7 hcmp/r run ]))) end   # => Integer  (helper resolved)
print ((typeof (do [ 3 7 rcmp/r run ]))) end   # => Error    (deep's self-call unresolved)
```

The sort algorithms themselves recurse fine — they are dispatched by name
through the namespace, not handed in as a value. The breakage is specific to
recursion reached *via* a passed-in function.

**Design impact:** the `natural` (alphanumeric) comparator was rewritten
from a clean recursive scanner into a **bounded iterative loop** with cursor
state in single-cell Arrays (`sort.aql:110-157`), precisely so it stays
callable when a sort invokes it through the comparator parameter.

### 1.4 🟠 A function value's free words resolve in the *running* module

An exported comparator that calls a private helper works when called
directly, but **fails when a sort in a different module invokes it** — the
helper resolves in the caller's module, not the definition's. Splitting
`comparator.aql` from `sort.aql` made `Sort.natural` raise
`undefined_word: natural-go` the moment `Sort.merge` (in the other module)
drove it.

**Design impact:** comparators and algorithms **must share one module**.
The planned two-file split was abandoned for a single `sort.aql`; this is
documented in `CLAUDE.md` and the file header.

### 1.5 🟠 Combinators: one captured function survives a module hop, two do not

`reverse` (a lambda capturing one comparator) composes through a sort across
modules. A combinator capturing **two** functions where one is a
cross-module comparator fails when invoked. This is why `by-key` captures
only the key-extractor and orders the keys with the built-in `cmp`, and why
the planned `then` (chain two comparators) was **dropped**.

### 1.6 🟡 Reference/passing quirks (a cheat-sheet)

All verified:

| Form | Result |
|------|--------|
| `def f inc/r` (bare) | 🔴 doesn't bind — later `f` is `undefined word: f` |
| `def f (inc/r)` (parens) | ✅ binds the function value |
| `Sort.by-number` (namespace member, bare) | ✅ already a parked value — pass as-is |
| `Sort.by-number/r` | 🟠 double-steps / misbehaves — **don't** add `/r` to a namespace member |
| `5 5 cf` (bare, `cf` a bound function) | ✅ auto-dispatches on the two stack args |
| `5 inc/r apply` | ✅ the documented invoke form |
| `xs Sort.quick Sort.by-number wrap` | 🟡 `Sort.by-number` **auto-invokes** because a word follows it |

```aql
def f inc/r            # => later: error: [aql/undefined_word]: undefined word: f
def f (inc/r)          # => binds; 5 f/r apply  =>  6
```

The net user-facing rule (now in `AGENTS.md`): namespace comparators bare,
your own comparator word with `/r`, the built-in with `cmp/r`.

---

## 2. Collections & types

Two silent identity changes, each of which produced a wrong sort before
being tracked down.

### 2.1 🔴 `lst get i` with a bare `each` variable returns `None`

Indexing a **List** with the loop variable from `each` yields `None`;
indexing an **Array** is fine, and even `lst get (i add 0)` is fine:

```aql
def lst [10 20 30]
def _ (iota 3 each [var [[i]
  print ((`lst_get=${(lst get i)}  arr_get=${((make Array lst) get i)}`)) end 0
]])
# => lst_get=None  arr_get=10
# => lst_get=None  arr_get=20
# => lst_get=None  arr_get=30
```

The loop variable types as `Integer`, so this is genuinely surprising — only
the *List* `get` path mishandles it. **Workaround / rule:** copy the input to
`make Array` and index the array. Every sort does `def arr (make Array lst)`
first; `is-sorted` originally indexed the List directly and returned wrong
answers until switched to an array.

### 2.2 🔴 `slice` on a list of typed values stringifies the elements

```aql
print ((typeof ([3 1 2] get 0))) end             # => Integer
print ((typeof (([3 1 2] slice 0 2) get 0))) end # => ProperString
```

A sub-list of integers comes back as strings, and a later `cmp` then raises
`incomparable: cannot order ProperString and Integer`. **Workaround:** never
`slice` a value list — build sublists by index (`iota mid each [var [[i] lst get (i add off)]]`)
or, as the sorts do, operate in place on one backing Array with `(lo, hi)`
bounds. This is why no algorithm uses `slice` to divide its input.

### 2.3 🟡 `convert Array list` is unsupported; `make Array list` is the constructor

`convert` only does scalar/map conversions, so `convert Array someList`
errors. Use `make Array someList`. Both `make Array` and `convert List`
**preserve** element types (unlike `slice`).

---

## 3. Statements & control flow

### 3.1 🟡 `set` is void — never `def`-bind it

`arr set i v end` returns nothing; `def _ (arr set i v end)` is an error
("expected 1 return value"). Call it as a bare statement. (Same for any void
word.)

### 3.2 🟠 A bare non-void `if` leaks its value into the return

A bare `if cond [a] [b]` used as a *statement* (not the final expression)
leaves its value on the stack, so the function returns one value too many:

```aql
def f fn [[x:Integer] [Integer] [
  if (x gt 0) [ 99 ] [ 0 ]    # bare statement, but it yields a value
  x add 1
]]
print ((5 f)) end
# => error: [aql/type_error]: f: expected 1 return value(s), got 2
```

In `sort.aql` this was subtler: the `counting`/`pigeonhole` range-guard
`if (span gt 1e8) [ raise … ] [0]` leaked a `0` that rode along in the
returned List, surfacing as a stray `0` in the smoke output rather than a
hard error (the declared return type swallowed it). **Workaround:** bind the
guard — `def _g (if … [raise …] [0])`.

### 3.3 🟡 `each` body must yield a value

Every `each` iteration must leave exactly one value; loops that act only for
side effects push a sentinel `0`. Ubiquitous in the code.

### 3.4 🟠 `and` / `or` do not short-circuit

Both operands are always evaluated:

```aql
print ((false and (1 div 0 gt 0))) end
# => error: division by zero
```

So `and` cannot guard a risky second operand. **Workaround:** nest `if` for
bounds checks — `if (i lt n) [ … access i … ] [ … ]` rather than
`(i lt n) and (… access i …)`. This shows up in every loop that reads
`arr get (i add 1)` near a boundary.

---

## 4. Naming & reserved words 🟡

A surprising number of useful identifiers are built-in words and cannot be
used as a `def` name **or a parameter name**, and the collision is often
only reported at runtime:

```aql
def cmp fn [[b:Any a:Any] [Integer] [ 0 ]]
# => error: [aql/reserved_word]: def cmp: 'cmp' is a built-in word and cannot be redefined
```

Hit during the build: `cmp`, `reverse`, `sort`, `merge`, `inner`, `min`,
`max`, `range`, `find`, `filter`, `select`, `group`, `depth`. A parameter
named `cmp` collided (renamed to `comp`/`cmpf`); a local `range` collided
(renamed to `span`); a `depth` parameter collided (renamed to `lim`).
Namespace **export keys** are unaffected — `Sort.merge` / `Sort.reverse` are
fine as map keys; only top-level `def`/param names are reserved.

---

## 5. Numerics 🟡

Integer overflow is a **hard error at 63 bits**, not a silent wrap. A naive
comparator `a sub b` can overflow on extreme inputs, so the default
comparators use `lt`/`gt` (or the built-in `cmp`, which compares without
subtracting). The counting / pigeonhole / radix sorts range-guard before
allocating their tables. This is a *good* default — loud beats silent — just
worth designing around.

---

## 6. Tooling — the static checker (`aql check`) 🟠

`aql check` is valuable but has false positives precisely where this library
lives:

- The `def cf (comp/r)` cluster ([§1.2](#12-the-def-cf-compr-workaround-trips-the-static-checker)) — `undefined_word: cf`.
- The recursive `radix-msd` self-call — `no_signature`.

These surface even when checking a **test file**, transitively through the
imported `sort.aql`. There is no way to reach zero `check` errors without
contorting correct code, so the project treats `check` as **advisory**: the
divergence harness (`test/divergence/run.sh`) and CI (`ci/test.yml`) gate on
**interpreter == byte compiler** instead — which passed for all five suites
and all 25 algorithms. The box pattern ([§1.2](#12-the-def-cf-compr-workaround-trips-the-static-checker)) already removed the largest
cluster; what remains is a handful of genuine false positives.

There is also a **test-framework** limitation worth recording:
`Test.run-spec` (the declarative spec runner) cannot dispatch a subject word
that takes a **Function** argument — i.e. the comparison sorts. Comparators
*as* subjects (`a b Sort.natural`) and the no-comparator distribution sorts
dispatch fine, so the declarative unit-spec (`test/sort_unit_spec.aql`)
covers those, and the comparison sorts are covered imperatively
(`test/sort_unit_test.aql`) and by the property-spec
(`test/sort_prop_spec.aql`), whose bodies are arbitrary code.

---

## 7. Build / environment 🟠

`git clone` of the aql source is blocked by the egress proxy; the GitHub
**codeload tarball** is not:

```
$ git clone https://github.com/aql-lang/aql …
fatal: unable to access '…': The requested URL returned error: 403

$ curl -fsSL -o /dev/null -w "%{http_code}" \
    https://codeload.github.com/aql-lang/aql/tar.gz/12a44e0…
200
```

Both the SessionStart hook (`.claude/hooks/session-start.sh`) and the
divergence harness fetch via `codeload.github.com/.../tar.gz/<ref>` so a
fresh remote session can build `aql` without a clone.

---

## 8. How these shaped the library (summary)

| Issue | Design consequence |
|-------|--------------------|
| §1.2 checker rejects `def cf (comp/r)` | Array-**box** comparator threading everywhere |
| §1.3 recursion-via-param fails | `natural` is **iterative**, not recursive |
| §1.4 free words resolve in running module | **single-file** `sort.aql` (no `comparator.aql`) |
| §1.5 two-capture combinator fails | `by-key` uses built-in `cmp`; `then` **dropped** |
| §2.1 / §2.2 List `get`/`slice` corruption | sorts copy to `make Array` and work on **index bounds** |
| §6 checker false positives | `aql check` is **advisory**; gate on interpreter == compiler |
| §7 clone blocked | hook + harness fetch via **codeload tarball** |

---

## 9. What worked well

It would be unfair to list only the rough edges. These made the build
genuinely pleasant:

- **Named-word recursion** is solid — quicksort, mergesort, heapsort,
  bitonic, stooge, slow, and recursive MSD radix all recurse by name with no
  trouble (the [§1.3](#13-a-recursive-helper-reached-through-a-function-param-fails-to-resolve) caveat is *only* about recursion reached through a
  passed-in value).
- **The built-in `cmp`** is a polymorphic three-way comparator
  (`3 cmp 7 => -1`, `"a" cmp "b" => -1`) — every default comparator is a
  one-liner over it.
- **Lambdas / closures** via `[params] => [body]` capture their enclosing
  scope cleanly — `reverse` is a four-token combinator.
- **`iota` / `each` / `fold`** are an ergonomic iteration trio; with
  single-cell Arrays for mutable state they express every bounded loop the
  language's lack of `while` would otherwise make awkward.
- **`make Array` / `convert List`** round-trip values with full type
  fidelity (the contrast that makes [§2.2](#22-slice-on-a-list-of-typed-values-stringifies-the-elements) so surprising).
- **Interpreter ↔ byte-compiler agreement held throughout.** Every suite,
  including the keystone cross-agreement property (each algorithm must equal
  the stable `Sort.merge`, 100 runs × 15 algorithms), produced byte-identical
  output under `aql X` and `aql --compile X`. For a library whose correctness
  *is* "all 25 algorithms agree", that guarantee was the bedrock the whole
  test strategy rests on.

---

## 10. Suggested upstream fixes (prioritized)

1. **Teach `aql check` about `def x (param/r)` and recursive self-calls.**
   This single fix removes every false positive this library hit and would
   let `check` return to gating ([§1.2](#12-the-def-cf-compr-workaround-trips-the-static-checker), [§6](#6-tooling--the-static-checker-aql-check)).
2. **Make List `get` with an `each` variable, and `slice` on a value List,
   either type-preserving or a loud error** — never a silent `None` /
   stringification ([§2.1](#21-lst-get-i-with-a-bare-each-variable-returns-none), [§2.2](#22-slice-on-a-list-of-typed-values-stringifies-the-elements)). These are the only 🔴s here.
3. **Lift the one-shot restriction on parking a Function parameter with
   `/r`** ([§1.1](#11-parking-a-function-parameter-with-r-is-one-shot)) — it forces the bind-once dance and, with #1, the box.
4. **Resolve a function value's free words (incl. recursion) in its
   *defining* module**, so library authors can split files ([§1.3](#13-a-recursive-helper-reached-through-a-function-param-fails-to-resolve), [§1.4](#14-a-function-values-free-words-resolve-in-the-running-module)).
5. **Report reserved-word collisions at parse/check time**, not at runtime
   ([§4](#4-naming--reserved-words-)).
6. **Let `Test.run-spec` dispatch subjects that take a Function argument**
   ([§6](#6-tooling--the-static-checker-aql-check)), so declarative specs can cover higher-order words.

*Report generated while building `Sort` against `aql @ 12a44e0`. Every
snippet was executed against that build; outputs are reproduced verbatim.*
