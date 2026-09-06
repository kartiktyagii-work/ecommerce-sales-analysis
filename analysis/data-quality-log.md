# Data quality log

One row per decision made while profiling and cleaning. This file is the difference between
*"I cleaned the data"* and being able to say **what** you cleaned, **how much** of it, and **why**
when someone asks in an interview — which they will.

> **Nothing is pre-filled here on purpose.** An earlier version of this file listed the defects to
> look for. That turns discovery into a checklist. Seven defects were injected from a menu of
> sixteen, at rates between 0.04% and 0.6% — you have to find them. See `HINTS.md` D1.3 for the
> *method*, not the answers.

---

## The three treatments

Every defect gets exactly one, and choosing is the actual analyst work:

| Treatment | When | Example |
|---|---|---|
| **Fix** | The true value is recoverable, no information is lost | `' West '` → `'West'`; `'1,234.56'` → `1234.56` |
| **Quarantine** | Row is unusable, but must not silently vanish | negative quantity → `core.rejected` with a reason |
| **Keep and flag** | Looks wrong, is real | **negative profit** — this is half your analysis. Never filter it |

**Quarantine, never delete.** `clean + rejected = staged` is a check you can run. A `WHERE` clause
is not.

---

## Log

| # | Issue found | Where | How I detected it | Decision | Rows | Why |
|---|---|---|---|---|---|---|
| 1 | | | | | | |
| 2 | | | | | | |
| 3 | | | | | | |

*Add rows as you go. The **How I detected it** column is for your own benefit — on the telecom
project nobody hands you a hint file, and this becomes your method.*

---

## Grain statement

State it once, explicitly, immediately after profiling. Before you model anything.

> One row of `core.fact_order_line` represents ________________________________.

Proved by: `______________________________________` (the query, and what it returned).

And for the second fact table, because the mismatch between them is the main modelling trap:

> One row of `core.fact_return` represents ________________________________.

---

## Reconciliation record

Fill in after the Day 1 gate passes. Keep the numbers — the Day 3 DAX gate checks against them.

| Metric | Staged | Clean | Rejected | Tie? |
|---|---|---|---|---|
| Rows | | | | |
| `sum(sales)` | | | | |
| `sum(profit)` | | | | |
| `sum(quantity)` | | | | |
| Distinct orders | | | | |
| Distinct customers | | | | |

**Overall return rate:** ______ % *(expect roughly 8%; 20-40% means the returns join fanned out)*

---

## Definitions I am committing to

**P§3.4** — a definition is a political object. Write yours down before someone else picks one
for you. These go into the README verbatim.

| Term | My definition | Why this one |
|---|---|---|
| Revenue | | |
| Profit / margin | | |
| An "order" | | |
| Return rate | | |
| Active customer | | |
| Repeat customer | | |
