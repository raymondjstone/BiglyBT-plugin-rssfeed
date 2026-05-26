# BiglyBT RSSFeed Scanner — sortable fork

A fork of the BiglyBT **RSSFeed Scanner** plugin (`org.kmallan.azureus.rssfeed`,
originally by kmallan, then maintained by Parg and others on the BiglyBT side)
that adds **sortable filter rules** — both column-driven sorts and a one-click
**Smart Sort** that reorders rules so the matcher hits the right ones first.

Everything else in the plugin is upstream behaviour: it polls RSS / Atom feeds,
matches each item against a user-defined filter list, and hands matching items
off to BiglyBT as torrent downloads (or fails them via FAIL rules). For the
upstream change history see [`ChangeLog.txt`](ChangeLog.txt).

This fork is currently versioned **1.8.6.1** on top of upstream 1.8.6. The
plugin renames itself to *"RSSFeed Scanner (sortable fork)"* in the BiglyBT
plugin list so you can tell it apart from a stock install.

---

## What this fork adds

The vanilla plugin only lets you reorder filter rules one row at a time, via
the up/down arrows on the toolbar next to the filter table. That is fine when
you have ten rules. It stops being fine somewhere around fifty.

This fork adds three things on top of that:

1. **Click a column header to sort by it.** Name, Type, and Mode are
   clickable; clicking the same header again flips ascending / descending. The
   active column shows the standard SWT up/down triangle.
2. **A "Smart Sort" toolbar button** at the bottom of the filter toolbar.
   One click reorders the entire filter list using a fixed, opinionated
   ordering described in detail below.
3. **Sorts persist.** The reordered list is written back to `rssfeed.options`
   exactly as if you had manually shuffled rows. Restart BiglyBT and the new
   order is still there. The up/down arrows still work too, and using them
   clears the active sort indicator because the column ordering no longer
   reflects what is on screen.

There are no new config switches and no new file formats. If you uninstall the
fork and put the upstream jar back, the rules just load in whatever order they
were last saved in.

---

## Why filter order matters at all

The matcher walks the filter list **from top to bottom and stops at the first
hit.** That single sentence is the whole reason this fork exists.

It means:

- **Order is precedence.** A rule that lives above another rule wins ties.
- **A broad rule placed above a narrow rule will swallow items the narrow
  rule was meant to catch.** This is the classic footgun. If you have a
  generic `1080p` PASS rule sitting above a specific `ShowName.*1080p.*WEB`
  PASS rule, the generic rule wins and the specific rule never fires.
- **FAIL rules only work if they sit above the PASS rules they need to
  veto.** A FAIL rule is how you say "I never want this release group / this
  language / this re-encode, even though it matches one of my PASS rules."
  If a PASS rule above it already grabbed the item, the FAIL rule sees
  nothing.

So "sort the rules nicely" is not a cosmetic feature — getting the order wrong
silently changes what gets downloaded. Smart Sort is a one-click way to put
the list into an order where those traps are unlikely to fire.

---

## Smart Sort: the algorithm

When you click the Smart Sort button, every filter rule is sorted by the
following key, in this exact priority:

1. **Enabled rules first, disabled rules last.**
2. Within enabled, **FAIL rules (`mode = 1`) before PASS rules (`mode = 0`).**
3. Then **group by the first alphanumeric character of the expression**
   (case-folded, A..Z then 0..9), skipping any leading non-alphanumeric
   characters like `^`, `(`, `.`, or whitespace.
4. Within each letter group, **reverse-alphabetical by the expression**
   (compared from the first alphanumeric character onward, case-insensitive).

The implementation is in `View.applySmartSort()` (and `firstAlphanumeric` /
`sortableText`) in `org/kmallan/azureus/rssfeed/View.java`. It reads the
current order off the table — so any unsaved up/down moves are picked up —
sorts the snapshot, writes it back through `Config.replaceFilters(...)`, and
rebuilds the table.

### Why each layer is the way it is

The four-layer key is not arbitrary. Each layer is chosen to put rules that
matter first where matching will actually see them first.

#### 1. Enabled rules first, disabled last

Disabled rules never match, so they cost the matcher nothing — but they cost
*you* something, because they clutter the top of the table where you are
scanning to figure out what is actually live.

Pushing disabled rules to the bottom keeps the visible top of the filter list
aligned with the rules the scanner will actually evaluate. It also makes it
much harder to lose a disabled rule among the active ones; a temporarily
disabled rule that drifts up into the active block is exactly the kind of
thing that causes "I swear I turned that off" debugging sessions.

This is the cheapest layer of the sort and the one with the highest
information-value-per-pixel, so it goes first.

#### 2. Within enabled rules, FAIL rules before PASS rules

FAIL rules exist to **veto** items that a later PASS rule would otherwise
grab. The canonical example: a PASS rule for `ShowName` plus a FAIL rule for
`ShowName.*GERMAN` to keep dubs out of your English library. The FAIL rule
*has* to be hit before the PASS rule, otherwise the PASS rule already
matched and the item is queued.

Concretely, the `MODE_*` constants in `FilterBean.java` are:

```
MODE_PASS = 0
MODE_FAIL = 1
```

so the Smart Sort comparator uses `Integer.compare(b.modeIndex, a.modeIndex)`
to put `MODE_FAIL` ahead of `MODE_PASS`.

If you organise your filter list any other way — alphabetical, chronological,
"the order I added them" — you will *eventually* add a PASS rule above a FAIL
rule that should have caught one of its items, and the FAIL rule will be
silently dead. Smart Sort makes that mistake impossible to make by hand,
because every FAIL rule is hoisted above every PASS rule on every sort.

#### 3. Group by the first alphanumeric character of the expression

Within "enabled FAIL rules" and "enabled PASS rules", we still have to pick
*some* order. Pure alphabetical works, but it scatters related rules: a rule
for `ShowName.*Repack` ends up nowhere near a rule for `ShowName.*Proper`
just because `P` and `R` differ.

Grouping first by the leading alphanumeric character keeps everything that
starts with the same letter or digit contiguous. In practice rules that target
the same show, release group, or keyword almost always share that first
character, so this layer is what makes the list scannable by eye.

We deliberately **skip leading non-alphanumeric characters** when determining
the group. RSS-filter expressions are regex, so it is very common to anchor
them with `^`, or to wrap them in `(?:...)`, or to start with a literal `.`.
Without the skip, `^foo` and `foo` would end up in completely different
groups even though they obviously belong together. With the skip they both
land in the `F` bucket.

Digits (`0..9`) sort after letters (`A..Z`) under `Character.compare` for
uppercased ASCII, which means numeric expressions like `2160p` cluster at
the bottom of each PASS / FAIL block — a reasonable default since pure-digit
rules tend to be quality / resolution filters rather than show-specific ones.

#### 4. Reverse alphabetical inside each letter group

This is the layer that seems backwards until you remember layer 2.

Inside, say, the "S" group of PASS rules, you might have:

- `Show`
- `Show.*1080p`
- `Show.*1080p.*WEB-DL`

In forward alphabetical order, `Show` comes first — and `Show` is the
broadest of the three. Since the matcher stops at the first hit, `Show`
would consume everything and the more specific rules below it would never
fire.

Reversing the order inside each letter group puts longer, more specific
expressions above their shorter prefixes:

- `Show.*1080p.*WEB-DL`
- `Show.*1080p`
- `Show`

Now the strict rule gets first crack, and the broad rule only catches what
the strict rules didn't claim. This is the same logic as "specific routes
before catch-all routes" in any URL router; the filter table is just a
router whose request is "an RSS item" and whose response is "queue / fail /
fall through."

Reverse alphabetical is not a perfect proxy for specificity — a hand-built
ordering will always beat it on edge cases — but it is right *far* more
often than wrong, and it costs nothing to apply.

### What Smart Sort deliberately does *not* do

- It does **not** look at filter Type (Other / TV Show / Movie). Type-based
  ordering would be appealing but cuts across the FAIL-before-PASS rule,
  which is more important.
- It does **not** look at any of the per-rule metadata (categories, tags,
  store directory, size limits). Those affect what happens *after* a match,
  not whether a match happens, so they have no business influencing the
  scan order.
- It does **not** try to detect "X is a prefix of Y" relationships
  structurally. That would be a much more involved analysis and the
  reverse-alphabetical trick gets you most of the benefit for none of the
  complexity.

If Smart Sort produces an order you disagree with on a specific pair of
rules, fix it with the up/down arrows — that still works, it just clears
the sort indicator afterwards.

---

## Column-header sorting

Clicking the Name / Type / Mode header sorts by that column only.
Implementation lives in `View.sortFiltersByColumn(int)` and
`View.comparatorForColumn(int)`.

- **Name** — locale-aware, case- and accent-insensitive (`Collator` at
  `PRIMARY` strength).
- **Type** — by `FilterBean.getTypeIndex()`, with Name as a tiebreaker.
- **Mode** — by `FilterBean.getModeIndex()` (so PASS before FAIL ascending,
  or FAIL before PASS descending), with Name as a tiebreaker.

Click the same column again to flip ascending / descending. Like Smart Sort,
the new order is written back to `rssfeed.options` immediately.

Column sorting is mostly a "find a specific rule" tool. If you actually want
the table in an order that protects FAIL rules from being shadowed by PASS
rules, use Smart Sort — column-by-Mode alone won't do it because it
preserves the internal order within each mode.

---

## Installing

A prebuilt jar is committed in [`dist/`](dist/) so you do not have to set up
a JDK just to use the plugin:

- `dist/rssfeed.jar` — the file BiglyBT actually loads.
- `dist/rssfeed_1.8.6.1.jar` — the same content with the version stamped
  into the filename, kept as a frozen reference for this release.

### Step by step

1. **Close BiglyBT** before swapping the jar — BiglyBT keeps the file open
   while it is running and the new jar will only load on a clean start.

2. **Locate your BiglyBT plugins directory.** This is in your *user*
   configuration directory, not next to the BiglyBT install:

   | OS      | Path                                                       |
   | ------- | ---------------------------------------------------------- |
   | Windows | `%APPDATA%\BiglyBT\plugins\rssfeed\`                       |
   | Linux   | `~/.BiglyBT/plugins/rssfeed/`                              |
   | macOS   | `~/Library/Application Support/BiglyBT/plugins/rssfeed/`   |

   If you have ever installed the upstream RSSFeed Scanner plugin via
   *Tools → Plugins → Installation Wizard* this folder already exists and
   contains an older `rssfeed.jar`. If it does not exist yet, create it.

3. **Copy `dist/rssfeed.jar` into that folder**, replacing the existing
   `rssfeed.jar` if there is one. You can keep the versioned copy
   (`rssfeed_1.8.6.1.jar`) alongside it for reference, but only
   `rssfeed.jar` is loaded.

4. **Start BiglyBT.** Open *Tools → Plugins* — you should see
   **"RSSFeed Scanner (sortable fork)"** at version `1.8.6.1`.

5. **Verify the new UI.** Open the RSSFeed view (*View → RSSFeed*),
   switch to the *Options → Filter* tab, and look at the toolbar to the
   right of the filter table. There should be a **Filter** icon below the
   existing up / copy / remove / down buttons — that is the Smart Sort
   button. Column headers (Name / Type / Mode) should also be clickable
   now.

### Rolling back

If you want to drop back to the upstream plugin, just replace
`rssfeed.jar` with the upstream jar (BiglyBT's *Plugins → Installation
Wizard* can re-install it) and restart. The fork does not change the
config file format — your filters and feed URLs will load unchanged.

---

## Building from source

You only need this if you want to modify the plugin. The committed
`dist/rssfeed.jar` is what end users should install.

The fork ships two equivalent build scripts. Both produce
`dist/rssfeed.jar` (and a versioned copy `dist/rssfeed_<version>.jar`).

- **PowerShell:** `./build.ps1` — used when Ant is not installed. Compiles
  with `--release 8`, locates `javac` / `jar` from `Program Files\Java` if
  they are not on `PATH`, and produces both jars.
- **Ant:** `ant -f build.xml` — the upstream build, kept working.

Both expect `lib/BiglyBT.jar` to exist (copy it from your BiglyBT install
directory — `lib/BiglyBT.jar` is git-ignored on purpose) and
`json-io_2.5.2.1.jar` to sit at the repo root (it already does in this repo).

---

## Layout

```
org/kmallan/azureus/rssfeed/    - Java sources (FilterBean, View, Config, ...)
org/kmallan/resource/lang/      - Help.stf, Messages.properties (i18n)
org/kmallan/resource/icons/     - Toolbar icons (Filter.gif is the Smart Sort button)
lib/                            - Place BiglyBT.jar here for builds
build.ps1 / build.xml           - Build scripts (pick one)
ChangeLog.txt                   - Upstream change history
```

The smart-sort code lives almost entirely in `View.java`; the rest of the
diff against upstream is the toolbar button wiring, two new strings in
`Messages.properties`, a help section in `Help.stf`, and the version /
plugin-name bumps in `plugin.properties`.

---

## License

Same license as the upstream plugin — see [`license.txt`](license.txt).
