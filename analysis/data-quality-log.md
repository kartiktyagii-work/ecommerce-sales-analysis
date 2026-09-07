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
| 1 | Sales values contain thousands separators | `staging.orders.sales` | Numeric-shape regex in P5.1, then selected invalid values in P5.2 | Fix: remove commas, then cast to numeric | 18 | The numeric value is recoverable and no information is lost |
| 2 | Dates are in `M/D/YYYY` format rather than ISO | `staging.orders.order_date`, `ship_date` | Date-shape check in P6.1 and invalid-value inspection in P6.2 | Fix: parse the source date format before casting | 1,000,569 order dates and 1,000,569 ship dates | The dates are valid source dates; only their representation differs |
| 3 | Region has case and surrounding-whitespace variants | `staging.orders.region` | P4 normalized-vs-raw profile; four normalized regions collapse raw variants | Fix: trim and standardize case | 4 normalized region groups | This prevents split regional groups without changing the region meaning |
| 4 | Postal codes are four digits, including leading-zero codes | `staging.orders.postal_code` | P10.4 five-digit shape check | Fix: left-pad numeric postal codes to five characters; retain NULLs | 118,407 | Postal codes are identifiers, so restoring the leading zero preserves the value |
| 5 | Duplicate order/product pairs contain multiple row versions | `staging.orders` | P2 grain comparison: 764 excess rows; content fingerprint excludes technical `row_id` | Keep separate pending business investigation; do not deduplicate automatically | 764 excess rows across 764 pairs | The repeated pairs are not exact duplicates, so deleting one would risk losing information |
| 6 | Target regions have inconsistent labels and duplicate region/year rows | `staging.targets` | P9 normalized-region and duplicate region/year checks; raw rows also show `C`, `E`, `East Region`, and `Sth` aliases | Fix labels using an explicit mapping; quarantine duplicate target rows after confirming the intended record | 4 case-variant values; 2 excess duplicate rows | Target grain should be one region/year, but the source contains ambiguous maintenance damage |
| 7 | Target units contains an invalid placeholder | `staging.targets.units` | P9 target numeric-shape check; value inspection found `000s` | Fix: interpret `000s` as thousands and convert target values consistently; document the scale | 4 | The unit is a recoverable label, not a missing numeric target |
| 8 | Negative profit is present | `staging.orders.profit` | P10.7 range check | Keep and flag | 75,494 | Negative profit is a real business outcome and must remain in margin analysis |

*Add rows as you go. The **How I detected it** column is for your own benefit — on the telecom
project nobody hands you a hint file, and this becomes your method.*

---

## Grain statement

State it once, explicitly, immediately after profiling. Before you model anything.

> One row of `core.fact_order_line` represents one product line within one customer order.

Proved by: P2 grain comparison in `sql/02_profiling.sql`; `COUNT(*)` = 1,000,569 and
`COUNT(DISTINCT (order_id, product_id))` = 999,805, with 764 repeated pairs requiring
investigation rather than assuming the grain is unique.

And for the second fact table, because the mismatch between them is the main modelling trap:

> One row of `core.fact_return` represents one returned order event/status record.

Proved by: P8 returns profile in `sql/02_profiling.sql`; 30,727 source rows represent
27,682 distinct order IDs, with 3,045 repeated return rows, so returns must not be joined
to order lines as though they were line-grain data.

---

## Reconciliation record

Fill in after the Day 1 gate passes. Keep the numbers — the Day 3 DAX gate checks against them.

| Metric | Staged | Clean | Rejected | Tie? |
|---|---|---|---|---|
| Rows | 1,000,569 | pending cleaning | pending rejected table | pending |
| `sum(sales)` | pending | pending | pending | pending |
| `sum(profit)` | pending | pending | pending | pending |
| `sum(quantity)` | pending | pending | pending | pending |
| Distinct orders | pending | pending | pending | pending |
| Distinct customers | pending | pending | pending | pending |

**Overall return rate:** pending after cleaning/modeling *(returns currently contain 27,682 distinct order IDs)*

---

## Definitions I am committing to

**P§3.4** — a definition is a political object. Write yours down before someone else picks one
for you. These go into the README verbatim.

| Term | My definition | Why this one |
|---|---|---|
| Revenue | Sum of sales value on valid order lines | Matches the line-level financial measure |
| Profit / margin | Profit; margin is profit divided by revenue | Keeps negative profit visible and makes profitability comparable |
| An "order" | A distinct `order_id` | Orders contain multiple product lines |
| Return rate | Distinct returned orders divided by distinct orders | Prevents repeated return rows and line joins from inflating the rate |
| Active customer | A customer with at least one valid order line in the selected period | Ties activity to observable transactions |
| Repeat customer | A customer with orders on at least two distinct orders | Distinguishes repeat behavior from multi-line orders |
