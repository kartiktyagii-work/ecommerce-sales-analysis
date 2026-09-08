# E-Commerce Sales & Customer Performance Analysis

> End-to-end analytics case study: a vague stakeholder email → a ~1M-row SQL star schema →
> a validated measure layer → **three costed decisions**. Built against a dataset with planted
> business signals and injected data-quality defects, neither of which were known in advance.

| | |
|---|---|
| **Status** | SQL, model and analysis **complete and reconciled**. Power BI file assembles from [`powerbi/BUILD-RUNBOOK.md`](powerbi/BUILD-RUNBOOK.md) — see *What is and is not built* below |
| **Stack** | PostgreSQL 16 · SQL (window functions, CTEs, `EXPLAIN ANALYZE`) · Power BI · DAX |
| **Data** | Tableau Sample Superstore's real product and geography structure, scaled to **996,567 clean order lines** across 2018-2021, plus a returns file and a deliberately damaged regional targets file |
| **Scale** | 337,737 orders · 107,688 customers · 1,862 products · $218.6M revenue |
| **Start here** | [`STAKEHOLDER-BRIEF.md`](STAKEHOLDER-BRIEF.md) — the ask, as it would actually arrive |

---

## The business problem

Northwind Retail has grown revenue every year for four years. Profit has not kept pace. Finance
(Ritu) thinks it is discounting. Sales (Anand) thinks the furniture line is dragging. The Head of
Commercial (Priya) has a board meeting on Friday and needs **two or three things the company is
actually going to do**, each with a number attached — because someone will ask *"how much"* and
*"how do you know"*.

There is also a warning in her email: the last analyst told the board Central was the best region,
having counted returned orders as sales. So everything here has to be provable.

---

## Headline answers

### 1. What is happening?

Revenue grew **247%** over four years — $22.3M → $77.5M. In the same period **margin fell every
single year**: 27.17% → 24.02% → 21.27% → **18.78%**, a slide of **8.39 percentage points**.

2021 is where the two lines cross: **revenue +11.8%, profit −1.3%.** By December, profit was
running **13.6% below** the same month a year earlier.

| | 2018 | 2019 | 2020 | 2021 |
|---|---:|---:|---:|---:|
| Revenue | $22.34M | $49.52M | $69.30M | $77.45M |
| Profit | $6.07M | $11.90M | $14.74M | **$14.55M** |
| Margin | 27.17% | 24.02% | 21.27% | **18.78%** |
| Weighted discount | 7.28% | 9.57% | 12.35% | **14.89%** |
| AOV | $680.83 | $667.94 | $645.07 | $627.92 |

### 2. Why is it happening?

**A two-factor bridge splits 2021's $190,962 profit fall exactly** (`10_` SP-04, residual $0.00):

| | |
|---|---:|
| Growth in revenue *added* | **+$1,734,127** |
| The fall in margin rate *destroyed* | **−$1,925,089** |
| **Net change in profit** | **−$190,962** |

The company grew enough to earn $1.7M more and gave back $1.9M in margin doing it.

**Decomposing that margin fall by discount band** (`10_` SP-04b) shows it is not one problem:

| Driver | Effect | Share |
|---|---:|---:|
| **Mix** — revenue moving into deeper discount bands | −3.20 pp | 38% |
| **Rate** — margin falling *within* discounted bands | −2.92 pp | 35% |
| **Rate** — margin falling on business sold at **full price** | **−2.27 pp** | **27%** |
| **Total** | **−8.39 pp** | 100% |

So Finance is right about roughly **three-quarters** of it — and **27% of the decline happens on
business that was never discounted at all**, which no discount policy can fix.

### 3. What should the business do?

Three decisions, each with a number and a stated trade-off. All modelled on 2021.

---

## Decision 1 — Cap discounts per sub-category, not company-wide

**The evidence.** Margin falls monotonically with discount and crosses zero between the 20-29%
and 30-39% bands (`11_` DP-02):

| Discount band | Lines | Revenue | Margin |
|---|---:|---:|---:|
| 0% | 455,110 | $112.6M | **30.74%** |
| 1-9% | 112,711 | $24.8M | 26.59% |
| 10-19% | 188,955 | $39.3M | 19.23% |
| 20-29% | 111,672 | $21.5M | 8.61% |
| **30-39%** | 59,807 | $10.6M | **−3.47%** |
| 40-49% | 31,377 | $5.2M | −17.13% |
| 50-59% | 16,644 | $2.4M | −32.07% |
| 80-89% | 6,644 | $0.5M | −87.53% |

**Ritu's question, answered literally:** yes. Lines discounted 50%+ are **36,935 lines across
34,597 orders**, carrying **$4.60M of revenue at −45.82% margin — a loss of $2.11M**, of which
**$1.22M was in 2021 alone**, up from $9,458 in 2018.

**But a single company-wide cap is the wrong instrument.** Break-even discount varies by more than
50 points across the catalogue (`11_` DP-04):

| Break-even at | Sub-categories |
|---|---|
| **10%** | Tables |
| 15% | Bookcases |
| 20% | Machines, Supplies |
| 30% | Appliances, Chairs, Copiers, Storage |
| 35% | Phones |
| 40% | Accessories, Art |
| 45% | Fasteners, Furnishings |
| 50-60% | Envelopes, Labels, **Binders, Paper** |

A flat 30% cap punishes Binders (profitable to 60%) while still letting Tables sell at three times
its break-even.

**The recommendation, as a range.** Price elasticity is not observable in this data — there is no
record of an order that did not happen — so the answer is bounded, not guessed:

| Policy (2021) | Orders touched | Upper bound *(all survive)* | Lower bound *(all lost)* | Break-even survival |
|---|---:|---:|---:|---:|
| Flat 30% cap | 40,060 (32.5%) | +$3.49M | −$3.31M | **48.6%** |
| **Per-sub-category cap** | **30,108 (24.4%)** | **+$4.55M** | **−$1.72M** | **27.4%** |

**The per-sub-category cap recovers 30% more margin while touching 25% fewer orders, and needs
only 27% of affected orders to survive to break even instead of 49%.** That gap is the whole
argument for doing the harder version.

**Trade-off, stated:** the upper bound assumes every affected order still happens at the lower
discount. It certainly will not. The recommendation is defensible because it survives a wide range
of assumptions — at a 75% survival rate the per-sub-category cap still returns roughly **+$3.0M**
— not because the point estimate is right.

---

## Decision 2 — Investigate West's *full-price* margin, not its headcount

West has been arguing it is under-resourced. **On every measure the data can see, it is not**
(`13_` RP-02):

| | West | East | Central | South |
|---|---:|---:|---:|---:|
| Share of revenue | 35.4% | 28.0% | 20.8% | 15.9% |
| Share of profit | 30.3% | 30.2% | 21.4% | 18.1% |
| Revenue per customer | **$2,249** | $2,044 | $1,892 | $1,792 |
| Orders per customer | **3.49** | 3.15 | 2.90 | 2.78 |
| Weighted discount | 12.29% | 12.30% | 12.03% | 11.90% |
| Margin 2021 | **14.39%** | 21.55% | 19.79% | 23.34% |

West has the **highest** revenue and orders per customer, and its discount rate is within 0.4
points of every other region. It is not being run thin and it is not discounting harder.

**Three hypotheses were tested and two were killed:**

- *Product mix?* No. Furniture share is 27.8% in West against 27.9% in South, and mix-adjusting
  West to the company product mix moves its margin by **0.03 pp**.
- *Discounting?* No — see the table above.
- *Something in the base economics?* **Yes.** Filtering to lines sold at **zero discount**
  (`16_` !4):

| Full-price margin | 2018 | 2021 | Change |
|---|---:|---:|---:|
| **West** | 33.34% | **24.70%** | **−8.64 pp** |
| Central | 33.78% | 29.86% | −3.92 pp |
| East | 33.73% | 32.25% | −1.48 pp |
| South | 33.37% | 33.59% | **+0.23 pp** |

West is losing 8.6 margin points **on business it is not discounting**, while South has lost none.
That is a pricing, freight, or cost-to-serve question, and it is worth **$1.32M a year**: West sold
$14.88M at full price in 2021, and closing the 8.89-point gap to South's full-price margin is
$1,322,465.

That figure is deliberately the *full-price-only* one. West's total margin gap to South is 8.95
points on $28.94M — about $2.6M — but part of that is discounting, which Decision 1 already claims.
Counting it twice would inflate the case for both.

West is also **199.6% of the company's 2020-21 profit decline**: −$381,102 against a company total
of −$190,962. Every other region improved or held.

**Trade-off:** the data cannot say *why* West's unit economics deteriorated — there is no cost,
freight or promotion table. This recommendation buys an investigation, not an answer. It is worth
it because it is the largest single unexplained number in the company.

---

## Decision 3 — Fix acquisition before optimising retention

Revenue growth in 2021 was almost entirely existing customers buying more:

| | 2018 | 2019 | 2020 | 2021 |
|---|---:|---:|---:|---:|
| **New customers acquired** | 25,953 | 38,683 | 30,751 | **12,301** |
| Active customers | 25,953 | 50,699 | 66,004 | 66,351 |
| Orders per active customer | 1.26 | 1.46 | 1.63 | **1.86** |

**Acquisition fell 68% from its 2019 peak** while orders per customer rose 48%. The active base
was flat in 2021 (66,004 → 66,351). Growth is currently being manufactured from a base that stopped
growing — a mechanism with a visible ceiling.

Meanwhile **9,468 customers are classified at-risk high-value**: they hold **$32.9M of lifetime
revenue and $8.1M of lifetime profit**, and have been quiet for an average of **594 days**
(`12_` CA-04). Recovering even 10% of that profit is **$809,000**, against a win-back campaign that
costs a fraction of that.

**Trade-off:** win-back is the cheaper and faster of the two, but it is a one-off. The acquisition
collapse is the structural problem, and this analysis can size it but cannot explain it — the data
has no marketing spend, channel or campaign columns.

---

## Findings that changed the brief

Five results that contradict something a stakeholder said. Each is why this project produced a
different recommendation than the one it was pointed at:

1. **Furniture is not the cause of the decline.** Margin excluding Furniture fell 30.77% → 22.32%
   (−8.45 pp) against −8.39 pp including it. Removing the entire category changes the trajectory by
   0.06 pp. Furniture is a **level** problem — 27.7% of revenue but 15.7% of profit at 12.23%
   margin — not a **trend** problem. *(Anand's hypothesis: not supported.)*

2. **Returns are not eating anyone alive.** The return rate has been flat for four years:
   8.12% → 8.24% → 8.18% → 8.20%. And net margin after returns (**21.77%**) is *higher* than gross
   (21.62%), meaning returned orders were slightly *less* profitable than average. Returns cost
   $23.2M of revenue a year in gross terms, but they are not what changed. *(Ritu's second
   hypothesis: not supported.)*

3. **No product loses money. Not one of 1,862.** Losses live entirely in discount *bands*. This is
   the finding that redirects the whole recommendation: the answer is not "cut products", it is
   "stop selling good products at bad prices".

4. **Seven sub-categories are below the company margin in 48 of 48 months** — Tables, Chairs,
   Bookcases, Appliances, Storage, Supplies, Phones. Tables was outright *negative* in 9 of those
   months. "Chronic" is a different diagnosis from "worst", and needs a different fix.

5. **The targets file cannot support a performance conversation without caveats.** 17 rows using
   **10 spellings** of 4 regions, 3 rows recorded in thousands flagged only by a `Units` column,
   2 exact duplicates, and **no target at all for Central 2018** — which nobody noticed for four
   years.

Plus two structural facts worth having: **468 of 1,862 products (25.1%) make 80% of revenue**, and
**the top 10% of customers make 38.1% of it**.

---

## Definitions I am committing to

Written down before anyone else picked them. Full list and reasoning in
[`analysis/data-quality-log.md`](analysis/data-quality-log.md).

| Term | Definition |
|---|---|
| **Revenue** | `SUM(sales)` — after discount, **before** returns. Reconciles exactly to source. Net revenue is a separate, labelled measure |
| **Margin** | `SUM(profit) / SUM(sales)` — a ratio of sums, never an average of per-row ratios |
| **Return rate** | distinct returned orders ÷ distinct orders. Both sides at **order** grain |
| **Repeat customer** | ≥ 2 distinct **orders**. (Counting lines gives 94.0% instead of 72.4%) |
| **As-of date** | fixed at **2021-12-31**. Never `current_date` |

---

## How it was built

```
orders.csv (1,000,569 lines)  ─┐
returns.csv (30,727)          ─┼─→  staging (all text)  →  core (typed, star schema)  →  SQL analysis
targets.csv (17, damaged)     ─┘         │                        │                          │
                                    profiling + DQ log      indexes + 15-check gate     DAX + Power BI
```

**Seven tables.** `dim_date` (1,461) · `dim_customer` (107,688) · `dim_product` (1,862) ·
`dim_geography` (632) · `fact_order_line` (996,567, **line** grain) · `fact_return` (27,674,
**order** grain) · `fact_target` (15, region-year grain).

**The central modelling problem** is that returns are recorded per *order* and sales per *line*.
Joining them directly multiplies every return by that order's line count — which is exactly the bug
in Priya's email. `07_reconciliation.sql` measures that inflation deliberately: **3.23×**, turning
a true 8.19% return rate into a false 8.96% and reordering every category ranking. The model avoids
it by keeping `fact_return` at order grain with pre-aggregated measures, and by carrying a
denormalised `is_returned` flag built with `EXISTS` (a semi-join, which cannot fan out).

**Three gates, none skipped:**

| Gate | What it proves | Result |
|---|---|---|
| `07_reconciliation.sql` | `staging = clean + rejected = fact`, on rows, sales, profit, quantity, orders and customers | **15 of 15 PASS**, zero tolerance |
| `powerbi/dax-vs-sql-gate.md` | Every DAX measure equals its SQL answer | **All tiers pass**; 5 mismatches found and fixed, 4 of which produced a plausible-looking wrong number |
| `analysis/query-tuning.md` | The heaviest query is fast, and I know why | KPI aggregation **7,830 ms → 1,737 ms** |

**Data quality:** 14 logged decisions across three treatments — *fix* (recoverable),
*quarantine* (unusable, but auditable), *keep and flag* (looks wrong, is real). **4,002 rows
quarantined** with a reason, never deleted. **75,197 loss-making rows kept**, because they are the
analysis.

**Performance:** the model build originally took over 10 minutes. It was not the row count — three
dimensions created by `CREATE TABLE AS` in the same script had **no planner statistics**, so
Postgres assumed one row and chose a nested loop. `ANALYZE` after each create took it to **32
seconds**. Indexes then took the heaviest analytical query from 7.8 s to 1.7 s, and the honest
finding is recorded too: **they did nothing for the big scans**, because a query touching 60% of a
table is supposed to sequential-scan it.

---

## Self-assessment

Graded against `_sealed/_DATASET-KEY.md`, opened on Day 5. Full working in
[`analysis/learning-log.md`](analysis/learning-log.md).

**Planted business signals: 9 of 10.**

Found: discount creep · the three discount hotspots (Tables, Bookcases, Machines) · **all six
margin-cliff thresholds, each bracketed inside a 5-point band** · all four regional margin
trajectories including the sign on South · seasonality · **the exact rank order of all six return
hotspots**.

**Missed: the weak acquisition cohort.** Customers acquired April–September 2020 repeat at 55% of
normal. I grouped cohorts by acquisition *year*, which averages a six-month effect across twelve
months and hides it — and I explained the residual signal away as an observation-window artefact,
which was reasonable and wrong. Found only after opening the key: **54.8% of that cohort reordered
against 77.0% for the six months before it**. The query is now `12_` CA-03c, marked as a post-key
addition rather than quietly back-dated.

**Injected defects: 6 of 7 — and the 7th is not in the file.** The key says
`customer_id_two_names` was injected at 34 rows. It is not present:
`GROUP BY customer_id HAVING COUNT(DISTINCT customer_name) > 1` returns zero rows out of 1,000,569.
Reported as a disagreement with the key rather than claimed as a find. Separately,
`thousands_separator` was injected 400 times but **manifests only 18 times**, because only 4.48% of
sales values are ≥ 1,000 — a comma below a thousand has nothing to separate.

**Found but never planted** — five emergent results, of which the most useful is the 38 / 35 / 27
split of the margin decline. The generator planted discount creep and regional decay separately;
that they compose so that **27% of the fall is on full-price business** was not designed, and it is
what stops the recommendation from being one-sided.

---

## What is and is not built

Being precise about this, because a portfolio piece that overstates itself is worse than one that
does less.

**Complete, runnable, and verified against the database:**

- All 18 SQL files — build (`00`-`07`), analysis (`10`-`16`), gate values (`18`)
- The seven-table star schema, indexed, with PK/FK constraints and 15/15 reconciliation
- All 37 register questions answered, with the number recorded in
  [`analysis/questions.md`](analysis/questions.md)
- The 42-measure DAX layer, [`powerbi/measures.dax`](powerbi/measures.dax), each measure annotated
  with the SQL value it must equal
- A CVD-validated Power BI theme, [`powerbi/theme.json`](powerbi/theme.json)
- The complete data-quality log, query-tuning record, learning log and self-assessment

**Not yet built:** the `.pbix` itself. Power BI Desktop is a GUI, so the model, the measures, the
four page designs, the security configuration and the validation numbers are all specified in
[`powerbi/BUILD-RUNBOOK.md`](powerbi/BUILD-RUNBOOK.md) — roughly three hours of assembly with no
decisions left to make.

**Also outstanding: the Day 5 user test.** It requires a real person opening the file cold, and it
is not something that can be simulated — the whole value of it is finding out what a stranger
misreads. `analysis/uat-notes.md` has the protocol and the specific things to watch for.

---

## Repo layout

```
sql/                 build + analysis scripts, numbered in run order
  00-07              raw CSV -> staging -> core star schema -> indexes -> reconciliation gate
  10-16              the analysis, one file per question group
  18                 reference values for the DAX gate
analysis/            question register, data-quality log, query tuning, learning log, UAT protocol
powerbi/             measures.dax, theme.json, BUILD-RUNBOOK.md, dax-vs-sql-gate.md
_sealed/             dataset builder + key (opened Day 5)
```

## Data provenance — read before quoting this anywhere

The base data is the **Tableau Sample Superstore** extract (9,994 real order lines), scaled to
~1M rows by `_sealed/build_dataset.py`, which reuses the real product catalogue, geography and
category structure while generating 110,000 synthetic customers and ~338,000 synthetic orders. It
plants business signals and injects a randomly chosen subset of data-quality defects.

Say exactly this: **"Superstore's real product and geography structure, scaled to ~1M synthetic
transactions with deliberately planted signals and defects."** Do not describe it as production
data. Every number in this README is reproducible from a query in `sql/`.
