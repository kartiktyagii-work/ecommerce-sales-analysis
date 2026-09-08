# Day 3 gate — DAX vs SQL

The rule that makes the rest of the project trustworthy: **no measure goes on a page
until it has been shown to agree with the SQL that answered the same question.**

SQL and DAX are different engines with different filter semantics. A measure can be
syntactically fine, render a plausible number, and be wrong — and the failure is
silent. Two grains, two facts and a `SAMEPERIODLASTYEAR` in the model is more than
enough surface area for that.

## Method

1. New page, called `_gate`. Table visual, no slicers, no filters.
2. Rows: nothing. Values: the measure under test.
3. Compare against the SQL value in the table below.
4. Anything that does not match to the cent is a bug in the model, not a rounding
   difference — `numeric` in Postgres and `Fixed decimal` in Power BI are both exact.
5. Delete the page once every row matches. Keep the screenshot in `../assets/`.

Regenerate the reference values at any time:

```
psql -h 127.0.0.1 -U postgres -d ecommerce -f sql/18_gate_values.sql
```

## Tier 1 — unfiltered totals

These catch grain errors and broken relationships.

| Measure | SQL value | Source | Result |
|---|---:|---|---|
| `Revenue` | 218,617,012.65 | `10_` SP-06 | ✅ |
| `Profit` | 47,254,458.39 | `10_` SP-06 | ✅ |
| `Units` | 3,338,886 | `10_` SP-06 | ✅ |
| `Order Lines` | 996,567 | `10_` SP-06 | ✅ |
| `Orders` | 337,737 | `10_` SP-06 | ✅ |
| `Customers` | 107,688 | `10_` SP-06 | ✅ |
| `Discount Value` | 30,309,470.42 | `11_` DP-01 | ✅ |
| `Gross List Value` | 248,926,483.07 | `11_` DP-01 | ✅ |
| `Margin %` | 21.62% | `10_` SP-06 | ✅ |
| `AOV` | 647.30 | `10_` SP-08 | ✅ |
| `Discount % (weighted)` | 12.18% | `11_` DP-01 | ✅ |

## Tier 2 — filtered, one dimension at a time

These catch relationship direction and cross-filter errors. Each is the same measure
with one slicer applied.

| Measure | Filter | SQL value | Result |
|---|---|---:|---|
| `Revenue` | `dim_date[year] = 2021` | 77,452,785.56 | ✅ |
| `Profit` | `dim_date[year] = 2021` | 14,547,727.88 | ✅ |
| `Revenue` | `dim_geography[region] = West` | 77,313,380.96 | ✅ |
| `Revenue` | `dim_product[category] = Technology`, 2021 | 33,803,664.46 | ✅ |
| `Margin %` | `sub_category = Tables`, 2021 | −0.04% | ✅ |
| `Profit at 50%+ Discount` | 2021 | −1,223,143.11 | ✅ |
| `Revenue Target` | 2021, all regions | 77,654,941.71 | ✅ |

## Tier 3 — the ones that actually break

The four measures where DAX and SQL diverge most easily, and what each proves.

| Measure | SQL value | What it proves |
|---|---:|---|
| `Orders` | 337,737 | Grain. `COUNTROWS(fact_order_line)` returns 996,567 — 2.95× too high. Any measure with `Orders` in its denominator inherits the error, so AOV and return rate both fail with it. |
| `Return Rate %` | 8.19% | The fan-out. Measuring the numerator at line grain gives 8.96% and mis-ranks every category. `07_reconciliation.sql` G2 measures the inflation at 3.23×. |
| `Repeat Rate %` | 72.4% | Orders vs lines. Counting customers with ≥2 *lines* gives 94.0% — a 21.6-point error that looks entirely plausible on a card. |
| `Profit YoY %` (2021) | −1.3% | Time intelligence. If `dim_date` is not marked as a date table, `SAMEPERIODLASTYEAR` falls back on an auto date hierarchy and this drifts without erroring. |

## Tier 4 — cross-check by decomposition

The strongest test: something that must add up rather than merely match.

| Check | Expected | Result |
|---|---|---|
| `SUM(Revenue by region)` = `Revenue` | 4 regions sum to 218,617,012.65 | ✅ |
| `SUM(Revenue by category)` = `Revenue` | 3 categories sum to the same | ✅ |
| `Net Revenue` + `Returned Revenue` = `Revenue` | 195,391,669.92 + 23,225,342.73 | ✅ |
| `Margin Recovery (Upper)` at cap 0.30, 2021 | 3,491,277.01 vs `16_` !2 | ✅ |
| `Margin Recovery (Lower)` at cap 0.30, 2021 | −3,305,761.75 vs `16_` !2 | ✅ |
| `Break-even Survival Rate` at cap 0.30 | 48.6% vs `16_` !2b | ✅ |

## Mismatches found and fixed during the gate

Recorded because the fixes are the interesting part, not the passes.

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 1 | `AOV` read 219.37 against SQL's 647.30 | `AVERAGE(fact_order_line[sales])` — the average LINE value. The fact table is at line grain and an order averages 2.95 lines | `DIVIDE([Revenue], [Orders])`, with `Orders` as `DISTINCTCOUNT` |
| 2 | `Return Rate %` read 8.96% against SQL's 8.19% | Numerator counted returned order *lines*, denominator counted *orders*. Two grains in one ratio | Numerator from `fact_return` (already order grain) |
| 3 | `% of Total Revenue` did not respond to the year slicer | `CALCULATE([Revenue], ALL(fact_order_line))` strips **every** filter including the date | `REMOVEFILTERS(dim_product)` — remove only the dimension the share is measured across |
| 4 | `Profit at 30%+ Discount` ignored the discount-band slicer | `CALCULATE` replaces filters on a column by default | wrap the condition in `KEEPFILTERS` so it intersects rather than overrides |
| 5 | Month axis ordered Apr, Aug, Dec… | `month_name` sorted alphabetically | `Sort by column` → `month_no`. `04_dim_date.sql` includes `month_no` for exactly this |

Four of those five produced a number that looked completely reasonable on screen.
That is the argument for the gate: **wrong numbers here do not look wrong.**
