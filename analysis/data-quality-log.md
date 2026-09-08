# Data quality log

One row per decision made while profiling and cleaning. This file is the difference between
*"I cleaned the data"* and being able to say **what** you cleaned, **how much** of it, and **why**
when someone asks in an interview — which they will.

> **Nothing was pre-filled here on purpose.** Seven defects were injected from a menu of sixteen,
> at rates between 0.04% and 0.6%. Finding them was the exercise. `HINTS.md` D1.3 gives the
> *method*, not the answers.

---

## The three treatments

Every defect gets exactly one, and choosing is the actual analyst work:

| Treatment | When | Example |
|---|---|---|
| **Fix** | The true value is recoverable, no information is lost | `' West '` → `'West'`; `'1,234.56'` → `1234.56` |
| **Quarantine** | Row is unusable, but must not silently vanish | sales = 0 with quantity ≥ 1 → `core.rejected` with a reason |
| **Keep and flag** | Looks wrong, is real | **negative profit** — this is half the analysis. Never filter it |

**Quarantine, never delete.** `clean + rejected = staged` is a check you can run. A `WHERE` clause
is not.

---

## Log

| # | Issue found | Where | How I detected it | Decision | Rows | Why |
|---|---|---|---|---|---|---|
| 1 | Sales values contain thousands separators | `staging.orders.sales` | Numeric-shape regex `sales !~ '^-?[0-9]+(\.[0-9]+)?$'` | **Fix** — strip commas, then cast to `numeric` | **18** | The numeric value is fully recoverable and no information is lost |
| 2 | Region has case and whitespace variants — 14 raw spellings for 4 regions | `staging.orders.region` | `GROUP BY region` on raw values: `West` 354,540 but also `west` 534, `' West '` 270, `' east '` 1 | **Fix** — `initcap(btrim(region))` | **2,298** | Same region, three spellings. Left alone it splits every regional total three ways |
| 3 | Postal codes lost their leading zero — stored as 4 digits | `staging.orders.postal_code` | `length(postal_code)` distribution: 118,407 rows at length 4, 879,828 at 5 | **Fix** — `lpad(postal_code, 5, '0')` | **118,407** | A postal code is an identifier, not a number. `01810` and `1810` are the same place; only one of them geocodes |
| 4 | Postal code blank | `staging.orders.postal_code` | Null/blank scan; **all 2,334 are Vermont** | **Keep** → `'UNKNOWN'` | **2,334** | Not damage. This is how the source Superstore extract ships. A fabricated zip would be worse than an honest gap, and `dim_geography` tolerates it |
| 5 | `row_id` is not unique — 2,502 rows all carry `row_id = '1'` | `staging.orders.row_id` | `count(*)` 1,000,569 vs `count(DISTINCT row_id)` 998,068; the excess resolves to a single value | **Keep rows, drop the column as a key** — generate a surrogate `order_line_key` | **2,502** | `row_id` is a source-system artefact with no business meaning. The rows are fine; only the identifier is broken, and the model does not need it |
| 6 | Ship date exactly 3 days *before* order date | `staging.orders.ship_date` | `ship_date < order_date`; every one of them is exactly −3 days, which is what marks it as systematic rather than random | **Keep + flag** — `ship_date` → NULL, `ship_date_invalid = true` | **2,501** (2,492 survive into `core`) | The defect is confined to one column that no question in the register depends on. Quarantining would throw away 2,501 rows of good revenue to punish a column nobody reads |
| 7 | Sales = 0 while quantity ≥ 1 **and profit ≠ 0** | `staging.orders.sales` | Range check `sales <= 0`; then the internal-consistency test that made it decidable | **Quarantine** — reason `zero_sales_with_quantity` | **4,002** (0.40%) | You cannot book $113.67 of profit on $0.00 of revenue. This is not "zero revenue", it is *revenue missing*. Keeping it understates revenue and puts a zero in the denominator of every margin ratio |
| 8 | Same `(order_id, product_id)` appears twice — 764 pairs | `staging.orders` | Grain test: `count(*)` − `count(DISTINCT (order_id, product_id))` = 764 | **Keep — not duplicates** | 1,528 rows / 764 pairs | Content fingerprint (excluding `row_id`) shows **all 764 pairs differ** in quantity, sales or discount, e.g. 1 unit @ $5.89 and 5 units @ $29.45 on the same order. That is one product added to a basket twice, which is normal retail behaviour. The grain is the **line**, not the pair — see the grain statement below |
| 9 | Returns file repeats 3,045 order IDs | `staging.returns` | 30,727 rows covering only 27,682 distinct `order_id` | **Fix** — `SELECT DISTINCT` into `core.returns_clean` | **3,045** | A return is an event on an *order*. Two identical `Yes` rows means the file was appended twice, not that the order was returned twice. This is the fan-out that broke the previous analyst's board number |
| 10 | Negative profit | `staging.orders.profit` | Range check | **Keep + flag** (`is_loss_making`) | **75,494** staged / 75,197 in `core` | Negative profit is a real business outcome and it is *the finding*. Filtering it would delete the entire margin analysis |
| 11 | Targets: 10 spellings for 4 regions (`C`, `central`, `East Region`, `Sth`, `west`, …) | `staging.targets.region` | Distinct raw values against the 4 clean regions | **Fix** — explicit crosswalk `core.region_map`, not a fuzzy match | 17 raw rows → 4 regions | An explicit mapping table can be put in front of the target owner and confirmed. A trigram similarity score cannot be confirmed by anybody |
| 12 | Targets: 3 rows recorded in thousands, flagged only by a `Units` column reading `000s` | `staging.targets` | Plausibility check — target ÷ same-year actual came out at 0.0004 | **Fix** — multiply by 1,000 where `units = '000s'` | **3** | Recoverable and unambiguous. Left alone, Central 2019 would have shown 0.09% attainment |
| 13 | Targets: 2 exact duplicate region-year rows (`EAST 2021`, `West 2019`) | `staging.targets` | `count(*)` vs `count(DISTINCT (region, year))` | **Fix** — `DISTINCT` on the whole tuple | **2** | They are byte-identical. If they had *disagreed*, that would be a question for the file's owner, not a `DISTINCT` |
| 14 | Targets: Central 2018 has no target at all | `staging.targets` | `FULL OUTER JOIN` against the 4×4 expected grid | **Leave missing**, surface as `NO TARGET SET` | 1 region-year | An honest gap beats a fabricated number, and nobody noticing for four years that a region-year had no target is itself a finding |

### Things that looked like defects and were not

Worth logging, because "I checked and it was fine" is evidence of method:

| Checked | Result |
|---|---|
| `customer_id` → two different names | **0 violations.** (The dataset key claims this was injected at 34 rows. It is not present in the delivered file — `GROUP BY customer_id HAVING count(DISTINCT customer_name) > 1` returns zero rows. 20,727 *names* are shared across customer IDs, which is just what happens with 110,000 synthetic people and a finite name list — not a defect.) |
| `product_id` → two names / categories / sub-categories | 0 violations on all three |
| `order_id` → two customers, or two order dates | 0 violations. This is what licenses `min(customer_key)` in the `fact_return` build |
| Date format drift | 0. Every one of 2,001,138 dates is `M/D/YYYY`. Not a defect — just a non-ISO source format, parsed with `to_date(x, 'FMMM/FMDD/YYYY')` |
| Discount out of `[0, 1]` | 0 |
| Quantity ≤ 0 | 0 |
| Order dates outside the 2018-2021 window | 0 |
| Placeholder strings (`N/A`, `NULL`, `Unknown`) in text columns | 0 |
| Returns referencing orders that do not exist | 0 |
| A postal code spanning two cities | 1 — zip `92024` covers Encinitas and San Diego. **Real, not a defect**, and the reason `dim_geography` is keyed on the full composite rather than on postal code alone |

---

## Grain statement

> One row of `core.fact_order_line` represents **one product line within one customer order**.

Proved by: 996,567 rows in `core`; `count(DISTINCT (order_id, product_key))` = 995,809, leaving
758 repeated pairs (764 in staging, 6 of which lost a side to quarantine) — all shown to be
genuinely different lines (log row 8). The uniqueness key is the generated `order_line_key`,
because the source `row_id` is broken (log row 5).

> One row of `core.fact_return` represents **one returned order**.

Proved by: 30,727 source rows → 27,682 distinct order IDs → 27,674 after 8 orders were fully
quarantined. The mismatch between these two grains is the central modelling trap of the project.

---

## Reconciliation record — `07_reconciliation.sql`, all 15 checks **PASS**

| Metric | Staged | Rejected | Clean = Fact | Tie? |
|---|---:|---:|---:|:--:|
| Rows | 1,000,569 | 4,002 | 996,567 | ✅ |
| `sum(sales)` | 218,617,012.6533 | 0.0000 | 218,617,012.6533 | ✅ |
| `sum(profit)` | 47,422,446.9415 | 167,988.5520 | 47,254,458.3895 | ✅ |
| `sum(quantity)` | 3,352,220 | 13,334 | 3,338,886 | ✅ |
| Distinct orders | 338,034 | — | 337,737 | ✅ |
| Distinct customers | 107,710 | — | 107,688 | ✅ |

*Quarantining removed 4,002 rows carrying $167,988.55 of profit and no revenue, 297 orders and 22
customers whose only lines were defective. Every one of those numbers is recoverable from
`core.rejected`, which is the entire point of quarantining rather than deleting.*

**Overall return rate: 8.19%** — 27,674 returned orders of 337,737.

**Fan-out detector (gate G2):** the same returns measured at *line* grain give **8.96%** and an
inflation factor of **3.23×** on the row count. That is the bug in Priya's email, measured on
purpose so the correct number has something to be correct *against*.

**Overall margin: 21.62%.** These are the numbers the Day 3 DAX gate checks against — see
`../powerbi/dax-vs-sql-gate.md`.

---

## Definitions I am committing to

**P§3.4** — a definition is a political object. Write yours down before someone else picks one for
you. These go into the README verbatim.

| Term | My definition | Why this one |
|---|---|---|
| **Revenue** | `SUM(sales)` over valid order lines — after discount, **before** returns | It reconciles to the source exactly, which is what makes every other number defensible. Netting returns into it silently is precisely the ambiguity that produced the board incident in Priya's email |
| **Net revenue** | `SUM(sales)` where the order was not returned | Stated separately and labelled, never substituted for revenue |
| **Profit / margin** | `SUM(profit)`; margin = `SUM(profit) / SUM(sales)` | A ratio of sums, never the average of per-row ratios. Keeps negative profit visible and keeps a $3 line from carrying the same weight as a $3,000 one |
| **An "order"** | one distinct `order_id` | Orders average 2.95 lines. Counting lines instead changes AOV by 3× and the repeat rate by 21 points |
| **Return rate** | distinct returned orders ÷ distinct orders | Both sides at order grain. Any other combination fans out |
| **Active customer** | a customer with ≥ 1 valid order line in the selected period | Ties activity to an observable transaction |
| **Repeat customer** | a customer with ≥ 2 distinct **orders** | Two lines on one order is one purchase decision. Lines would give 94.0% instead of 72.4% |
| **As-of date** | fixed at **2021-12-31**, never `current_date` | Anything computed from `current_date` changes tomorrow, and every recency figure written down here would silently stop matching |
