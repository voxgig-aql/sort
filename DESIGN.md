# DESIGN — topological sort, and the ordering families beyond comparators

> **Status: design only. Nothing here is implemented.** No `sort.aql` word,
> no test, no doc page exists for any of it yet. This document is the
> argued plan: what to build, in what order, and — for the parts where
> boru's runtime forces the answer — what shape the code has to take.
> Sketches below are *shapes*, not implementations.

This repository ships 25 comparison sorts, 6 distribution sorts, 3 joke
sorts, 8 comparators/combinators and one predicate. Every one of them is
the same idea: **a total order over a List, supplied by a comparator.**

Two things are missing from that picture, and this document covers both:

- **Part I — topological sort**: ordering driven by *constraints between
  elements* rather than by a comparison of their values. A different
  input (a graph), a non-unique output, and a new failure mode (cycles).
- **Part II — "and similar"**: the catalogue of ordering algorithms a
  mature sorting library is expected to have and this one does not —
  selection, ranking, multi-key comparators, sorted-sequence operations —
  prioritised, with the naming hazards settled up front.

---

## 0. The decisions, at a glance

| # | Decision | Ruling | Why (one line) |
|---|----------|--------|----------------|
| 1 | Does topo sort belong in `Sort`? | **Yes**, as a comparator-driven word | With a comparator on the ready set it *is* "sort, restricted by edges" — the library's own idea, generalised |
| 2 | Engine | **Kahn**, not DFS | TCO does not cover a DFS body (§8.4); Kahn is a bounded loop, detects cycles for free, and layers fall out of it |
| 3 | Comparator | **Required**, like every comparison sort | Makes the determinism policy explicit at the call site, where a non-unique output demands it |
| 4 | Graph direction | `{a: [b c]}` means **a precedes b and c** (successors) | Matches `tsort(1)`; the reverse reading is a *silently valid* wrong answer (§3) |
| 5 | Dependency direction | A separate `Sort.invert` word, not a flag | Two named things beat one boolean nobody reads |
| 6 | Determinism | Ready set ordered by the comparator; **node ids projected through `sort`** | boru's `keys` is *insertion*-ordered — using it directly makes output depend on how the map was built (§4) |
| 7 | Cycles | **`raise cyclic`** with a structured payload | House style is coded errors; boru errors carry Lists, so the payload can hold the actual cycle (§5) |
| 8 | Layers | Ship `Sort.topo-layers` | Free from the same engine; the parallel-scheduling answer |
| 9 | Test keystone | **Changes** — validity + determinism, not equality-with-`merge` | Topological output is non-unique, so cross-agreement cannot be on identity (§9) |
| 10 | Node values | **Strings** (boru map keys are String/Atom only) | A hard runtime constraint, not a choice (§8.7) |

---

# Part I — Topological sort

## 1. Why it belongs here, and where the fit strains

The honest case against: this library sorts a `List` by a comparator and
returns a permutation of it. A topological sort takes a **`Map`** (a
graph), returns one of *many* valid answers, and can **fail**. Three of
the library's four defining properties change.

The case for, which wins: **with a comparator, a topological sort is a
sorting algorithm restricted by edges.** At each step the classic
algorithm has a *ready set* — the nodes with no unmet prerequisites — and
must pick one. Picking by comparator makes the whole thing a
generalisation of what this library already does:

- no edges at all ⇒ the ready set is everything ⇒ the output is exactly
  `Sort.merge comp lst`. **An empty graph degenerates to a plain sort.**
  That is the proof the word belongs in this namespace.
- edges present ⇒ the same comparator, applied to whatever the
  constraints currently allow.

So the strain is real but bounded, and the payoff is that a user already
holding `Sort.by-string`, `Sort.natural` or `Sort.reverse` can use every
one of them to order a dependency graph. No second vocabulary.

What this is **not**: a graph library. No shortest paths, no traversal
API, no graph type. The graph is a plain `Map`, in one direction, and the
only operations are the ones that produce an *order*.

## 2. The proposed surface

Four words. All follow the house convention — **arguments forward,
receiver (the graph) LAST**.

| Call | Returns | Notes |
|------|---------|-------|
| `Sort.topo comp graph` | `List` | A linear extension: every node exactly once, every edge respected. Raises `cyclic`. |
| `Sort.topo-layers comp graph` | `List` of `List` | Dependency "waves": layer 0 has no prerequisites, layer *k* depends only on layers `< k`. Raises `cyclic`. |
| `Sort.invert graph` | `Map` | Transpose: successors ⇄ dependencies. The direction adapter. |
| `Sort.edges-graph edges` | `Map` | `[[before after] …]` pair list → adjacency `Map`. The `tsort(1)` input shape. |
| `Sort.is-topo comp graph` *(optional)* | `Boolean` | Acyclicity test with no witness. Cheap; ship only if a caller wants the predicate without the raise. |

Piping form works identically (`graph Sort.topo comp end`), and the one
misbinding order is the same one the rest of the library documents:
`Sort.topo graph comp` reads the graph as the comparator.

Sketch of the intended call sites:

```boru
def g {build: ["test" "lint"], test: ["deploy"], lint: ["deploy"], deploy: []}

Sort.topo Sort.by-string g
# => ["build" "lint" "test" "deploy"]

Sort.topo-layers Sort.by-string g
# => [["build"] ["lint" "test"] ["deploy"]]
```

Note the second line of the first result: `lint` before `test` is the
*comparator's* choice — both were ready, and `"lint" < "test"`. That is
the whole design in one line.

## 3. Direction — the footgun, and the ruling

`{a: ["b"]}` is genuinely ambiguous, and this is the single most
dangerous thing about the whole family:

- **successors** reading — edge a→b — "a must come before b"
- **dependency** reading — "a needs b" — b must come before a

The two answers are **exact reverses of each other, and both are valid
topological orders** (of the graph and of its transpose). There is no
error, no cycle, no crash: a build system wired the wrong way simply runs
backwards. Silent, plausible, wrong — precisely the failure class this
repo's `AGENTS.md` already fights with its "Common mistakes" table.

Every library that got this right did it by **naming**, not by
documentation: Python's `graphlib` is unambiguous only because its
parameter is literally called `predecessors`; POSIX `tsort` because its
spec sentence says the pair `a b` means a precedes b.

**Ruling.** The canonical shape is **successors**: `{a: [b c]}` means
*a comes before b and c*. Three reasons:

1. It matches `tsort(1)`, the oldest and most widely known interface.
2. It is the shape Kahn's inner loop consumes; the alternative pays an
   inversion pass at ingest.
3. Isolated nodes are representable (`{a: []}`) — an edge list alone
   silently drops zero-degree nodes, which in a task graph means tasks
   that never run.

Users whose data is in dependency form (package manifests, `requires:`
lists — the common real-world shape) write `Sort.topo comp (Sort.invert
deps)`. One word, self-documenting at the call site, and `Sort.invert` is
independently useful.

**Rejected:** a `{direction: …}` option field. It moves the decision into
a runtime value nobody reads at the call site, which is where the
mistake is made.

**Documentation requirement:** state the direction in terms of the
*output* as well as the input — "the first element depends on nothing;
the last is depended on by nothing" — because that is the sentence a
caller can check against their own data.

## 4. Determinism — and a boru-specific landmine

A DAG on *n* nodes has between 1 and *n*! valid orders. There is no "the"
order, so a library must pick a policy and document it. (Counting the
valid orders is #P-complete — Brightwell & Winkler 1991 — so this is not
a gap that can be papered over with an "all orders" count.)

Determinism is not a nicety here. It is what makes output diffable,
builds reproducible, cache keys stable, and — for this repo specifically —
what lets a test assert `Assert.equal` on a List instead of running a
validity oracle.

**Policy: the comparator orders the ready set.** At each step, among all
currently-unblocked nodes, take the one the comparator ranks first. This
yields the lexicographically-smallest valid order under that comparator,
and it is why the comparator is mandatory rather than optional.

**Document the surprise, with an example.** This is *greedy-min-available*,
not "sort, then fix up". A low-ranking node that depends on a
high-ranking one lands *after* it:

```boru
def g {zebra: ["apple"], apple: []}
Sort.topo Sort.by-string g      # => ["zebra" "apple"]  — NOT alphabetical
```

Callers who expect "sorted, then repaired" will file this as a bug. It
is not; it is the only sane reading of "ordered as much as the
constraints allow".

### The landmine

boru has **two** map-iteration orders, and picking the wrong one makes
the output silently depend on how the caller happened to build the map:

| Expression | Order |
|---|---|
| `m keys`, `m vals`, `m each …` | **insertion** |
| `m sort`, `StructUtil.items m` | **key-sorted** |

Seeding the algorithm from raw `keys` means a graph built
`{c:… a:… b:…}` and the identical graph built `{a:… b:… c:…}` produce
different orders. Worse, it is invisible in tests written against
literal maps in source, and only shows up when a graph arrives from a
parse or a fold.

**Requirement: every node enumeration in this family — the seed scan and
the successor scan — goes through a sorted projection** (`keys (g sort)`,
or `StructUtil.items`), never raw `keys`. Then the comparator is the
*only* thing that decides order, which is the guarantee we want to
publish. The cost is one O(n log n) projection on a family that is
already O(V log V + E).

This deserves its own `###` subsection in `docs/explanation.md`, under
"The boru idioms it rests on" — it is exactly the kind of
language-constraint-forced design choice that file exists to record.

## 5. Cycles

A cycle is **expected input** for a dependency tool, not a programmer
error — but "there is a cycle" in a 5,000-node graph is unactionable.
The survey of prior art is a catalogue of insufficient answers: Erlang
returns bare `false`; npm and petgraph name *one* participating node;
Haskell's `topSort` does not detect cycles at all and returns a
non-topological permutation.

**Ruling: raise `cyclic`, with a structured payload.**

Raising (rather than returning a result map) is house style — every
failure in this library is a coded error caught with
`do […] error […]`, and `docs/reference.md` already has an
`## Errors at a glance` table to extend. The payload is what makes it
actionable, and boru supports it: an error raised in map form preserves
every extra key, including `List` values, readable as `e.cycle`.

```boru
raise {code: cyclic/q
       message: "Sort.topo: graph has a cycle (a -> b -> a)"
       cycle:     ["a" "b" "a"]     # a real path, first == last
       sorted:    [ … ]             # the acyclic prefix that could be ordered
       remaining: [ … ]}            # the residue: nodes on or downstream of a cycle
```

Three properties worth committing to, each cheap:

- **The witness is a path, not a set.** Kahn hands back the residue for
  free (every node whose in-degree never reached zero); a three-colour
  DFS *restricted to that residue* — usually a tiny fraction of the graph
  — yields the actual cycle path.
- **The witness is deterministic.** Python's `graphlib` explicitly leaves
  the choice undefined when several cycles exist. Seeding the search in
  sorted node order makes it defined, which costs nothing and makes error
  messages diffable.
- **Self-loops count.** `{a: ["a"]}` is a cycle. Kahn catches it for
  free; note that SCC-based detection does *not* (a self-loop's strongly
  connected component has one member), which is a classic bug.

**The phantom-cycle trap, to be pinned by a test:** if in-degrees are
counted from a raw edge list while adjacency is de-duplicated, a
duplicate edge deadlocks the algorithm and it reports a cycle that does
not exist. This is the most common hand-rolled-Kahn bug. In-degree must
be derived from the *same* de-duplicated adjacency the main loop walks.

## 6. Layers

`Sort.topo-layers comp g` returns a `List` of `List`s: layer 0 is every
node with no prerequisites, layer *k+1* is everything unblocked once all
of layer *k* is done. Same engine, one extra boundary in the loop, same
Θ(V+E).

It is strictly more informative than a flat order (it exposes the
available parallelism and the graph's critical depth), and each layer is
a **sorted `List`, not a set** — the Python `toposort` package yields
sets and had to grow a `sort=True` flag to patch the determinism hole
that created.

**Document the caveat, because it is the common misuse:** layer barriers
are *not* an optimal parallel schedule. A node in layer *k+1* needs only
its own predecessors finished, not all of layer *k*. Layers are for
reporting, visualisation and width analysis. (A genuine scheduler wants
an incremental "what is ready now" interface — see §11.)

## 7. The engine: Kahn, not DFS

| | Kahn (in-degree) | DFS reverse-postorder |
|---|---|---|
| Shape in boru | **one bounded loop** | recursion, or a hand-rolled frame stack |
| Host stack | O(1) | O(longest path) |
| Cycle detection | free (`emitted < |V|`) | needs 3 colours; a 2-state visited set silently misses cycles |
| Cycle residue | free | — |
| Comparator on ready set | natural (the ready set is explicit) | **impossible** — DFS cannot produce a lexicographic-minimum order |
| Layers | free (batch the frontier) | not available |

Kahn wins on every axis that matters here, and the comparator row is
decisive: the entire design rests on ordering the ready set, and DFS has
no ready set to order.

boru pushes the same way. TCO exists but does **not** cover a DFS body
(§8.4), so a recursive DFS keeps every frame alive — and chain-shaped
dependency graphs, the common case in build systems, are the worst case.
Measured on this build: a recursive DFS over a 5,000-node chain takes
~4.1 s, while an equivalent cursor loop handles 32,000 nodes in ~0.4 s.

**DFS still ships — as a subroutine**: the cycle-witness extractor over
the (tiny) residue, and an independent oracle in the property suite.

## 8. Implementation constraints in boru

These are not style preferences. Each one is a measured or verified
property of the current build, and each forces the shape of the code.

**8.1 — Accumulators must be `flex`.** Immutable `Map`/`List`
accumulation is *quadratic*: building an n-entry map by folding `set`
takes 211 ms at n=1000 and 11,403 ms at n=8000, against 26 ms and 52 ms
for the mutable `flex` equivalent — a **219× gap at n=8000**. In-degree
table, visited set, queue and output accumulator are all `flex`.
Convert back with `node` at the boundary so the returned value is a plain
immutable `List`, preserving the library's no-mutation contract
externally. (`Store` is not an option: `make Store` is a coded refusal.)

**8.2 — No `shift`, no `pop`, for two independent reasons.**
`FlexList shift` reallocates (measured quadratic: 7.3 s to drain 16,000
elements), so a textbook Kahn queue is O(n²). And both `pop` and `shift`
return **two** values — the container *and* the removed element — which
leaks a residual that the bytecode compiler refuses
(`residual shape beyond Stage 1`). The working shape is an **append-only
`flex` list plus an integer read cursor** in a one-cell flex list; it
measured linear (400 ms at n=32,000).

**8.3 — Loop, don't recurse; and mind the two opposite body-arity rules.**
There is no `while`. The idiom is `for N [body]` with an early `break`.
Inside a `fn`, a `for` body must net **zero** values, while an `each` body
must yield **exactly one** (push a sentinel `0`). Getting either wrong is
a hard error, not a warning. This matches how every existing algorithm in
`sort.aql` is written.

**8.4 — TCO will not save a recursive traversal.** Tail-call optimisation
is real, but requires that nothing pends below the call *and* that the
callee re-binds every name the caller's frame holds. A traversal carrying
a visited/in-degree binding through body-local `def`s fails the second
condition, and combining results after the recursive call fails the
first.

**8.5 — `and`/`or` do not short-circuit.** `(g has (u)) and ((g get (u)) size gt 0)`
evaluates both sides. Guard with nested `if`.

**8.6 — Name collisions.** Reserved (cannot be bound): `node`, `keys`,
`vals`, `has`, `depth`, `stack`, `walk`, `find`, `list`, `scan`, `sort`,
`merge`, `filter`, `min`, `max`, `range`, `cmp`, `reverse`. Verified free
and idiomatic for this family: `nd`, `ks`, `adj`, `indeg`, `frontier`,
`queue`, `cur`, `out`, `seen`, `visited`, `edges`, `nodes`, `cycle`,
`level`, `order`. Also: capitalised names bind *types*, so all graph
state is lowercase.

**8.7 — Nodes are Strings.** boru map keys must be `String` or `Atom`
(they are the same slot), so `Sort.topo` cannot accept arbitrary values
as nodes. The signature takes a `Map` with String keys, and the docs must
say so plainly. Callers with richer node values key by id and re-project
afterwards. *(A future `key:`-function variant could lift this; it is not
worth the complexity in v1 — see §12.)*

**8.8 — Guard the raise.** A `raise` inside a bare `if` used as a
statement leaks the else-branch value into the return. The house idiom —
already used at all five existing raise sites — is to bind the guard:
`def _g (if (cond) [ … raise … ] [0])`.

**8.9 — The comparator must be reachable.** `Sort.topo` calls a
comparator through a `Function` parameter, so it must live in `sort.aql`
alongside the comparators, exactly like every other algorithm here. This
is the single-module rule the library already documents, and it is also
why `boru check` stays advisory for this repo: its known false positives
are precisely on first-class function values.

Shape of the loop, elided — this is the skeleton the constraints above
force, not an implementation:

```boru
def topo-sort fn [
  [comp:Function g:Map] [List] [
    def ks    (keys (g sort))   # 8.1/§4 — sorted projection, never raw `keys`
    def indeg (flex {})         # 8.1 — flex, not Map
    def queue (flex [])         # 8.2 — append-only …
    def cur   (flex [0])        #      … plus a read cursor, never `shift`
    def out   (flex [])
    …                           # seed, then drain, ordering the ready set by comp
    node out                    # 8.1 — freeze at the boundary
  ]
]
```

## 9. Testing — the keystone property changes

This repo's stated keystone is **cross-agreement**: every algorithm must
return the same ordering as the stable `Sort.merge`. **That property does
not transfer**, and saying so explicitly matters more than any single
test — a valid topological order is not unique, so two correct
implementations may legitimately disagree.

The correct analogue is two properties:

1. **Validity** — the output is a permutation of the node set (P1) *and*
   every edge is respected (P2: build a `pos` map, assert
   `pos[u] < pos[v]` for every edge u→v). P2 is *the* correctness
   property, and it is Θ(V+E).
2. **Determinism** — the output is byte-identical across runs, and
   across *storage permutations* of the same graph (same nodes, same
   edges, different map construction order). This is the property that
   catches the §4 landmine, and it is the one most libraries lack.

Further properties worth pinning, in rough value order:

| Property | Catches |
|---|---|
| Empty graph ⇒ plain sort: `Sort.topo comp g` with no edges `deq` `Sort.merge comp nodes` | the §1 degeneracy claim — the reason the word is in this namespace |
| Cycle always detected: DAG + one back-edge ⇒ raises; self-loop ⇒ raises; 2-cycle ⇒ raises | 2-colour detection bugs, missing self-loop handling |
| Witness validity: reported `cycle` has first == last, every consecutive pair is a real edge | witness-extraction bugs (the strongest single cycle test) |
| Duplicate-edge invariance: duplicating every edge changes nothing and reports no cycle | the §5 phantom-cycle bug |
| Layer soundness: `flatten(layers)` is P1∧P2-valid; `layer(u) < layer(v)` for every edge | off-by-one and barrier errors |
| Isolated nodes survive | the classic edge-list-only bug |

**Oracles.** For n ≤ 8, brute-force all permutations and filter by P2 to
get the exact set of valid orders — then assert membership *and*
lexicographic minimality. For larger graphs, generate a **planted-order
random DAG** (pick a permutation, emit edges only forward along it) so a
valid answer is known by construction.

**A non-property, worth a comment in the suite so nobody "fixes" it:**
`sort(invert(g)) == reverse(sort(g))` is **false** in general. Both sides
are valid orders; they need not be equal.

**Suite placement.** These go in `test/sort_prop_test.aql` and
`test/sort_unit_test.aql`. They **cannot** go in the `_spec` files: those
are driven by `Test.run-spec`, which cannot dispatch a subject taking a
`Function` argument — and every word here takes a comparator.

## 10. What landing it requires

Beyond `sort.aql` and the tests, this repo has a wide surface that CI
checks for drift. A new family is not done until:

- `docs/reference.md` — a `## Constraint-driven ordering` section
  (between the joke sorts and the predicate) with the family table, plus
  a `cyclic` row in `## Errors at a glance`.
- `docs/explanation.md` — a `### Why the graph is a successors map` under
  "Design choices specific to this library", and a `###` on the
  insertion-vs-sorted iteration landmine (§4) under "The boru idioms it
  rests on".
- `docs/how-to.md` — an `## Order a dependency graph` recipe, its entry
  in the anchor index, and a row in the `| Goal | Use |` table.
- `AGENTS.md` — call shapes in the API tables, and at least two rows in
  "Common mistakes" (the direction footgun; greedy-min-available vs
  "sorted then repaired").
- `api.json` — `word_specs` entries, the `cyclic` code in
  `conventions.errors`.
- **Both** copies of the skill (`.claude/skills/sort-aql/SKILL.md` and
  `plugins/sort-aql/skills/sort-aql/SKILL.md`) — a CI job `diff`s them
  and fails on drift.
- `test/divergence/run.sh` `SUITES` and a step in
  `.github/workflows/test.yml` if any new suite file is added.
- `README.md` — the "What you get" list.

## 11. Deferred, with reasons

- **Streaming / incremental interface** (`prepare` / `ready` / `done`, as
  in Python's `graphlib` and petgraph's `Topo`). This is what a real
  parallel executor wants — a node unblocks the moment *its own*
  predecessors finish, not when a whole layer does. Deferred because it
  needs a stateful handle value; the sibling `stats` repo's `Summary`
  accumulator is the house pattern to copy when it lands.
- **`Sort.all-topo`** (enumerate every valid order, Knuth–Szwarcfiter).
  Useful only as a test oracle, and with no lazy sequences in boru the
  output is a memory hazard. Build it inside the test suite if needed,
  not as a public word.
- **Critical path / slack (PERT/CPM)**. Nearly free once layering exists
  (layer = longest path length; ALAP − ASAP = slack), but it is project
  scheduling, not ordering — a `schedule.aql` companion, not `Sort`.
- **SCC / condensation.** The principled way to "sort a cyclic graph
  anyway". Worth having if users ask; not needed for v1, where the cycle
  witness covers the diagnostic need.
- **Transitive reduction** — a high-value lint ("you declared a→c but it
  is already implied"), unique for DAGs only. Natural follow-on.

**Declined outright**, each with the reason to paste into a reply:

- **Dependency/version resolution** — NP-hard constraint solving
  (SAT/CDCL: PubGrub, libsolv). Not a sort.
- **Precedence-constrained scheduling** (minimise makespan or Σw·C) —
  NP-hard (Lawler 1978). The ordering half is what we ship.
- **Counting linear extensions** — #P-complete (Brightwell & Winkler
  1991). Never ship a `count-topo`.
- **A `precedes` predicate as the graph input** — materialising the
  relation costs O(V²) calls, the relation may be non-transitive (so a
  comparison sort on it produces nonsense), and cycles become
  undetectable. The comparator is a *tiebreak*, never the edge relation.

## 12. Open questions

1. **Is `Sort.is-topo` worth a word**, or is `do [Sort.topo …] error […]`
   enough? (Leaning: skip it; the raise already carries more information.)
2. **Should `Sort.topo` auto-declare nodes that appear only as
   successors** (`{a: ["b"]}` with no `b` key), or raise? Auto-declaring
   is friendlier; raising catches manifest typos. (Leaning: auto-declare,
   and document that the node set is keys ∪ values — forgetting that
   union is the second most common hand-rolled bug.)
3. **A `key:`-function variant** to lift the String-node restriction
   (§8.7) — worth it, or does it drag the whole first-class-function
   checker friction back in for a rare case? (Leaning: defer.)
4. **Does `Sort.edges-graph` belong at all**, or should the pair-list
   form be a docs recipe using existing `fold`? (Leaning: ship it — the
   `tsort(1)` shape is what people paste from build logs.)

---

# Part II — "And similar": the ordering gap catalogue

Topological sort is one of several ordering capabilities absent here.
This part is the survey, so the roadmap is a decision rather than a
series of one-off requests.

## 13. Naming hazards — settle these before writing any of it

Four collisions will cause silent confusion if not ruled on up front:

| Hazard | Ruling |
|---|---|
| **`Sort.merge` is merge SORT** — but C++, Python, Erlang and `sort -m` all use "merge" for *merging two sorted sequences* | Two-way merge is **`Sort.merge-sorted`**; k-way is **`Sort.merge-k`**. Document the divergence loudly — this is the most confusable name in the library. |
| `ArrayUtil.rank` already means *number of dimensions* (APL rank) | Use the plural **`Sort.ranks`** (it returns a List anyway). |
| C++ `unique` means *adjacent* collapse; `ArrayUtil.unique` is global | Name it **`Sort.dedupe`**, never `unique`. |
| "top-k" reads as *largest*, but under an ascending comparator the first k are *smallest* | Ship **`Sort.least`** / **`Sort.greatest`** (Guava's and Swift's choice). Never `top-k`. |

Two things already exist and must be aligned with, not duplicated:
**`ArrayUtil.grade`** is argsort without a comparator (so ours is
`Sort.grade`, documented as "`ArrayUtil.grade` plus a comparator plus
stability"), and **`ArrayUtil.at`** already *is* apply-permutation — so
only `invert-perm` is missing.

## 14. The families

**SHIP — multi-key comparator combinators.** The most conspicuous gap for
real data work, and the cheapest thing in this document: `Sort.then-by`
(fall through to a second comparator on ties) plus a variadic
`Sort.chain`. Roughly ten lines each, no new concepts, and they compose
with every existing comparator — this is SQL's `ORDER BY a, b DESC` for
the sibling `boru:query` and `boru:report` modules. Also here:
`Sort.total` (a comparator over boru's cross-type total order via
`tcmp`) and `Sort.nulls-first`/`nulls-last`.

> **Blocker to resolve first — see the appendix note on combinator
> drift.** On current boru `main`, feeding a *bare* namespace comparator
> into a combinator (`(Sort.by-number Sort.reverse)`) raises
> `uncalled_function`; it needs `Sort.by-number/r`. Since every word in
> this group is a combinator, the calling convention for combinator
> arguments has to be settled — and the docs corrected — before any of
> them is written.

> **Latent defect found while surveying:** `Sort.by-generic` is
> implemented with `cmp`, which is *same-family only*, so
> `[1 "a"] Sort.merge Sort.by-generic` raises `incomparable` despite the
> name promising polymorphism. `Sort.total` (using `tcmp`) is the
> three-line fix and should land with this family.

**SHIP — selection and partial sorting.** The only family where the
library is asymptotically leaving performance on the table: 25 sorts and
no way to get the median or the top 10 without sorting everything.
`Sort.nth` (quickselect — expected O(n)), `Sort.median`, `Sort.least` /
`Sort.greatest` (bounded heap, O(n log k) time and **O(k)** memory),
`Sort.partial`, `Sort.partition` / `stable-partition` / `is-partitioned`,
`Sort.min-by` / `max-by` / `minmax`. For k=100 of n=10⁶ that is ~20×
fewer comparisons and ~10⁴× less working memory than sorting; for the
median, ~6×. Those multipliers are *realised* here rather than
theoretical, because this library's comparators (`natural` rescans digit
runs on every call) make comparison count the dominant cost.

**SHIP — rank and permutation.** `Sort.grade` (stable argsort) is
load-bearing infrastructure: `ranks`, multi-column sorting, cached-key
decoration and stable topological tiebreaks all reduce to it, so it comes
before the words that need it. Then `Sort.ranks` with an explicit tie
policy (`min`/`max`/`dense`/`ordinal`/`average` — SQL's `RANK` /
`DENSE_RANK` / `ROW_NUMBER`), which is absent from the entire boru
stdlib, and `Sort.invert-perm`.

**SHIP — `Sort.by-cached-key`.** The Schwartzian transform: evaluate the
key once per element instead of twice per comparison. At n=10⁶ that is
4×10⁷ key evaluations down to 10⁶ — **40×** — and it directly rescues
this library's own expensive `natural` and `case-insensitive`
comparators. It also *is* the collation-key pattern (`strxfrm`,
`CollationKey`), which is the honest answer to locale-aware sorting
without shipping megabytes of CLDR tables.

**SHIP — operations on already-sorted input.** `Sort.lower-bound` /
`upper-bound` / `equal-range` / `find-sorted` / `partition-point` (one
shared binary-search helper, four wrappers), then `Sort.merge-sorted` /
`merge-k`, then the set operations `union` / `intersect` / `diff` /
`dedupe` / `insert-sorted`. The asymptotic case is stark: the current
idiom for intersection is `ArrayUtil.member`, which is O(n·m) — at
n=m=10⁴ the sorted-input version is ~5000× faster.

**CONSIDER — sortedness diagnostics.** `Sort.is-sorted-until` (which also
fixes a real wart: `Sort.is-sorted` has no early exit and scans the whole
list even after finding a violation), `Sort.runs`, `Sort.inversions`,
`Sort.kendall-tau`, a seeded `Sort.shuffle`, and `Sort.check-comparator`
(validate that a user comparator is actually a total order — no library
ships this, and every library documents the corruption it causes).

**OUT OF SCOPE**, with the reason:

- **External / streaming sort** — needs the `fileio` capability, which
  would move `sort.aql` from "pure, sandbox-safe, zero-capability" to
  capability-gated. If ever built: a separate `sort-external.aql`.
- **Lazy / iterator sorting** — boru has no generator protocol, and
  sorting cannot stream anyway.
- **In-place mutating variants** — violates the library's no-mutation
  contract, which is a stated convention in `api.json`.
- **Suffix arrays** — a text index, not an ordering utility (see the
  sibling `trie` repo).
- **Full UCA / locale collation** — megabytes of CLDR data. Expose
  `by-cached-key` and document the code-point-order caveat instead.

## 15. Prioritised order

Ordering rationale: combinators first (no dependencies, unblock
everything else), `grade` before its dependents, one binary-search helper
before the four words that wrap it, selection before the sorted-set
operations (bigger asymptotic payoff per line), diagnostics last (they
consume the others).

| # | Words | Depends on | Why here |
|---|-------|-----------|----------|
| 1 | `then-by`, `chain`, `total`, `nulls-first/last` | — | ~10 lines each; fixes the `by-generic` defect; unblocks multi-key everywhere |
| 2 | `grade` | `merge` (present) | Substrate for ranks, cached keys, stable tiebreaks |
| 3 | `by-cached-key` | `grade` | 40× fewer key evaluations; rescues `natural`/`case-insensitive` |
| 4 | **`topo`, `topo-layers`, `invert`, `edges-graph`** | `grade` (for stable tiebreaks) | Part I — the capability being requested |
| 5 | `nth`, `median`, `least`, `greatest`, `partial` | quick-partition (present) | Largest asymptotic win available |
| 6 | `lower-bound`, `upper-bound`, `equal-range`, `partition-point` | one `bound` helper | Gateway to every sorted-input operation |
| 7 | `merge-sorted`, `merge-k`, `union`, `intersect`, `diff`, `dedupe` | 6, plus the heap from 5 | O(n+m) vs today's O(n·m) |
| 8 | `ranks`, `invert-perm`, `is-permutation-of` | `grade` | What `boru:query` / `boru:report` need |
| 9 | `is-sorted-until`, `runs`, `inversions`, `shuffle`, `check-comparator` | `merge-span` | Diagnostics; closes the property-suite loop |

Topological sort sits at #4 rather than #1 deliberately: `grade` gives it
stable tiebreaking for free, and the three combinator words above it are
each an afternoon's work that everything else benefits from. If it is
wanted sooner it can move to #1 at the cost of implementing the
ready-set ordering directly rather than through `grade`.

---

## Appendix — measured facts behind these rulings

Verified against the current `boru` build while preparing this document.

| Fact | Measurement | Consequence |
|---|---|---|
| Immutable `Map set` accumulation is quadratic | 211 ms (n=1k) → 11,403 ms (n=8k); `flex` equivalent 26 ms → 52 ms | §8.1 — accumulators must be `flex` (219× at n=8k) |
| `FlexList shift` reallocates | 255 ms (n=2k) → 7,308 ms (n=16k) | §8.2 — append + cursor, never `shift` |
| Cursor loop is linear | 59 / 142 / 400 ms at n=2k / 8k / 32k | §8.2 — the working queue shape |
| Recursive DFS vs loop | 4.1 s for a 5,000-node chain vs 0.4 s for 32,000 nodes | §7 — Kahn, not DFS |
| `keys` is insertion-ordered; `m sort` / `StructUtil.items` are key-sorted | direct observation | §4 — the determinism landmine |
| Errors carry structured payloads | `raise {code: … cycle: ["a" "b" "a"]}` round-trips; `e.cycle` is a real `List` of size 3 | §5 — the cycle witness is expressible |
| Map keys must be String/Atom | `{} set 7 "x"` fails at check with `no_signature` | §8.7 — nodes are Strings |
| `Store` is not user-constructible | `make Store` → `[boru/unsupported]` | §8.1 — `flex` is the only mutable option |
| `and` / `or` do not short-circuit | side-effect probe fires on both branches | §8.5 |

### Note — combinator drift on boru `main` (found while preparing this doc)

The library is pinned to boru `6185620`. Against boru `main` (`162ba5e`)
the **combinator calling convention has changed**, and the currently
documented form no longer runs:

```boru
(nums Sort.quick (Sort.by-number Sort.reverse) end)    # main: uncalled_function
(nums Sort.quick (Sort.by-number/r Sort.reverse) end)  # main: [8 5 3]  ✓
```

A bare namespace comparator still works when passed **directly to a
sort** (`Sort.quick Sort.by-number`); it fails only when passed **into a
combinator**, where forward collection now invokes it instead of
deferring it. `(slen/r Sort.by-key)` — a user word already carrying `/r`
— is unaffected.

This contradicts a rule stated across `AGENTS.md`, `README.md`,
`docs/reference.md`, both `SKILL.md` copies and the "Common mistakes"
table, all of which currently list `Sort.by-number/r` as the *error* and
the bare form as correct. It also breaks `test/sort_smoke_test.aql:58`
(the first combinator line; everything above it passes).

It is a pinned-version question, not a defect in this repo, and the
decision belongs to the maintainer: **re-pin to `main` and invert the
documented rule for combinator arguments**, or **stay pinned** and note
the ceiling. Either way it must be settled before the combinator family
(#1 in §15) is built, since every word in that group takes a comparator
as a combinator argument. `Sort.topo` itself is unaffected — it takes its
comparator in a sort-style argument position, which still accepts the
bare form.
