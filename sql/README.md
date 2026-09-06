# SQL — run in numbered order

Two phases. **Build** (01-07) turns three raw files into a trustworthy star schema. **Analysis**
(10-16) answers the question register in `../analysis/questions.md` — the one *you* wrote.

Every file is a skeleton with `-- TODO` markers. The comments tell you what the block is for and
which trap lives near it. They do **not** give you the query. That is the project.

## Build

| File | Does | Gate |
|---|---|---|
| `00_setup.sql` | Database + schemas. Already run, idempotent | — |
| `01_staging_load.sql` | Raw CSV → `staging.*`, every column `text`. No casting | row counts tie to the files |
| `02_profiling.sql` | Nulls, distincts, ranges, dupes, **grain proof**, defect hunt | grain written down as a sentence |
| `03_cleaning.sql` | Cast and normalise into `core`. Quarantine into `core.rejected` with a reason | `clean + rejected = staged` |
| `04_dim_date.sql` | Contiguous calendar from `generate_series` | 1,461 rows, no gaps |
| `05_dimensional_model.sql` | 4 dims + 3 facts, PKs, FKs | FKs resolve, no orphans |
| `06_indexes.sql` | Indexes, with `EXPLAIN ANALYZE` before and after | both timings recorded |
| `07_reconciliation.sql` | `core` totals vs `core.orders_clean` | **every row PASS** |

## Analysis

| File | Answers | Notes |
|---|---|---|
| `10_sales_performance.sql` | `SP*` | AOV is per **order**, not per line |
| `11_product_performance.sql` | `PP*` | Holds the margin/discount analysis — the query that becomes a decision |
| `12_customer_analytics.sql` | `CA*` | RFM, cohort retention. Timebox the cohort query |
| `13_regional_performance.sql` | `RP*` | |
| `14_returns_analysis.sql` | `RT*` | Two different grains — mind the join |
| `15_targets.sql` | `TG*` | The messy second source |
| `16_discount_counterfactual.sql` | the decision | **Day 3 only**, after the change request |

## Three schemas, deliberately

- **`staging`** — raw text, never edited in place, always reloadable. Nothing reads it except
  `03_cleaning.sql`.
- **`core`** — typed, cleaned, modelled. Everything Power BI connects to lives here.
- *(no `mart` layer here — at ~1M rows you do not need one. The telecom project does, and that is
  where you build one.)*

## Two things that will bite you

**Grain.** Two of your three sources are at different grains from each other. Joining across
grains multiplies rows silently — nothing errors, the number is just wrong. Count rows before and
after every join. `../_shared/ANALYST-PRIMER.md` §3.1.

**Casting money.** `numeric`, never `float`. `float` gives you `1234.5600000000001` at the
reconciliation gate and twenty minutes deciding whether a rounding difference is a real problem.
