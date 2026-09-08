# Learning log

One line every time I got stuck, used a hint, or changed my mind. Not curated — messy and honest
beats tidy and retrospective.

---

## Stuck / unstuck

| Day | What I was stuck on | What unstuck me | Hint used |
|---|---|---|---|
| 1 | `05_dimensional_model.sql` ran **> 10 minutes** on the fact build and I assumed 1M rows was just slow | `pg_stat_activity` showed the backend `active` with no wait event — burning CPU, not waiting on I/O. That ruled out disk and pointed at the plan. The dimensions are created by `CREATE TABLE AS` in the same script and **had no statistics**, so the planner assumed one row and chose a nested loop over 107,688 rows × 996,567. `ANALYZE` after each create → **32 seconds**. | none |
| 1 | Deciding between quarantine and keep-and-flag for the ship-date defect | Asking which *columns* the defect damages, rather than which rows. `ship_date` feeds nothing in the register; `sales` feeds everything. So the ship-date rows stay and the zero-sales rows go | D1.4 |
| 1 | Whether 764 repeated `(order_id, product_id)` pairs were duplicates | Fingerprinting the rows on content excluding `row_id`. **All 764 differ** — 1 unit @ $5.89 and 5 units @ $29.45 of the same product on one order. Not duplicates: the grain is the line, not the pair. Nearly deleted 764 real order lines | D1.3 |
| 1 | `row_id` not unique and I could not see the pattern | `GROUP BY row_id HAVING count(*) > 1` returned exactly one group of 2,502. It is not "duplicates scattered about", it is one value overwritten | none |
| 2 | Whether "consistently underperforming" meant worst-on-average | Re-read the question. It is a **count of periods below threshold**. Tables averages 5.25% margin *and* is below the company margin in 48 of 48 months — two different facts that need two different fixes | D2.7 |
| 2 | The West margin gap. Assumed product mix, then assumed discounting | Both were wrong, and testing them was the work. Mix is identical across regions (27.6-27.9% Furniture) and a mix-adjusted margin moves West by 0.03 pp. Discount rate is within 0.4 pp of every region. So I filtered to `discount = 0` — and West's **full-price** margin fell 33.34% → 24.70% while South's was flat. Three hypotheses, two killed, and the third is the finding | none |
| 3 | The lower bound of the counterfactual felt wrong — losing deeply-discounted lines came out *positive*, because those lines lose money | Because the bound was constructed at the wrong grain. Customers do not abandon a *line*, they abandon an *order* — and that order also carries full-price lines. Rebuilt at order grain and the bound became properly negative (−$3.31M) | D3.1 |
| 3 | Wanted to hide `customer_name` from a role and could not find the setting | There is no setting. **RLS filters rows; it cannot hide a column.** Column security is OLS, and Power BI Desktop has no UI for it — it needs Tabular Editor. Spent 20 minutes looking for a checkbox that does not exist, which is how I learned the distinction properly | none |

---

## Day 0 — question derivation score

- **Matched:** 17 of 25 (15 clean, 2 partial)
- **Missed:** 8

  | Question I missed | Why I did not think of it |
  |---|---|
  | Total revenue, volume, profit | Every question I derived was *comparative*. I never asked for a level |
  | Average order value | Same reason, plus AOV is not in Priya's email — she asks "how are we doing", and I translated that straight to growth |
  | Seasonality by calendar month | I had "trend over time" and assumed that covered it. It does not: a trend and a seasonal shape are different questions |
  | Consistently underperforming products | I had "worst products" and thought that was the same question |
  | Product Pareto | Never occurred to me to ask about concentration until I saw it on the list |
  | Active vs unique customer counts | Baseline again |
  | Average customer order frequency | Baseline again |
  | High-return products that are also top sellers | I had return rate and I had top sellers; I did not think to *intersect* them |

  **The pattern:** six of the eight are *baseline magnitude* questions. I am comfortable asking
  "how has this changed" and I forget to ask "how big is it". Priya needs "how are we doing"
  before she can hear "why is it happening" — Page 1 needs a KPI row.

- **Extra (mine, not on the list):** 7 — the whole `DP` discounting group (4) and the whole `TA`
  targets group (3).

  | Question I added | Why it is worth keeping |
  |---|---|
  | DP-04 — at what discount does margin turn negative, by sub-category | This became the project's headline recommendation. It is on nobody's list because it comes from Ritu's *forwarded* note, not Priya's bullets — which is exactly where the real question was hiding |
  | TA-03 — are the targets reliable enough to use at all | Promotes a data-quality check into a business question. Nobody had asked whether the target file was trustworthy; the answer changes whether TA-01 can be shown to a board |

---

## Day 3 — the change request

Written during the 25-minute re-scope block, **before** rebuilding anything.

**Promoted:**
- `DP-01`…`DP-04` discounting → from a section of Page 2 to the whole of **Page 1**
- `TA-01`…`TA-03` targets → from "if there is time" to a committed panel on Page 3
- New: the counterfactual (`16_discount_counterfactual.sql`), which was not in the register at all

**Demoted / parked:**
- `CA-03` cohort retention — already written, stays on Page 4, no further work
- `CA-04` RFM — already written, keeps its card row, loses its planned drill-through page
- The customer deep-dive page as a *concept*: Page 4 becomes Customer **and** Returns combined

**New work, and its cost:**

| Item | Estimate | Actual |
|---|---|---|
| Rebuild Page 1 around margin recovery | 45 min | 60 min — the what-if parameter took longer than expected |
| Counterfactual SQL + what-if parameter | 60 min | 75 min — the lower bound had to be rebuilt at order grain |
| Target vs actual on Page 3 | 30 min | 30 min |
| Hide customer names | 30 min | 50 min — RLS turned out to be the wrong tool (see stuck/unstuck) |
| **Total** | **2h 45m** | **3h 35m** |

**What I cut to make room, and what that costs the deliverable:**
- The customer drill-through detail page. Cost: you can no longer click a customer and see their
  order history; the ranked table is the end of the road. Priya explicitly said she would not
  complain, so this is the cheapest thing to lose.
- The mobile layout — already out of scope.
- Field parameters on Page 2. The matrix now shows a fixed set of six measures instead of a
  user-chosen one. Cost: a reader who wants a seventh measure has to ask.

**Net time impact:** roughly **+1h 35m over** against ~2h freed by parking the customer deep-dive,
so ≈ **25 minutes net negative**. That is the normal outcome of a change request. The correct
response is to cut something visible and say so, which is what this section is.

> In a real job this goes back to the stakeholder as an email. It is what protects you when
> someone asks in March why retention was not covered.

---

## Day 5 — self-assessment against `_sealed/_DATASET-KEY.md`

### Planted business signals: **9 found of 10**

| Planted signal | Found? | Where I found it / why I missed it |
|---|:--:|---|
| Discount creep | ✅ | `11_` DP-01. Weighted rate 7.28% → 14.89%; $30.3M given away over four years |
| Discount hotspots: Tables, Bookcases, Machines | ✅ | `11_` PP-05 ranked exactly those three worst: Machines −16.12 pp, Tables −11.99, Bookcases −10.52 |
| Margin cliff at Tables 16%, Bookcases 19%, Machines 22%, Supplies 24%, Storage 34%, Chairs 36% | ✅ | `11_` DP-04. **Every one of the six true thresholds falls inside the band I bracketed it in** (Tables last-profitable 10% / first-loss 15%; Bookcases 15/20; Machines 20/25; Supplies 20/25; Storage 30/35; Chairs 30/35). 5-point bands, so this is as precise as the method allows |
| West: volume +23.5%/yr, margin −2.8%/yr | ✅ | `13_` RP-01/RP-04. Fastest growth (311% vs 247%), steepest margin fall, and 199.6% of the company's 2021 profit decline |
| East −0.4%/yr, Central −1.1%/yr, South +0.2%/yr | ✅ | `16_` !4 isolates this cleanly on full-price lines: West −8.64 pp, Central −3.92, East −1.48, **South +0.23** — the sign on South matches the key exactly |
| Seasonality: peak Sep/Nov/Dec, trough Jan | ✅ | `10_` SP-07. Dec 135.5, Nov 133.9, Sep 124.5; Jan 64.3 |
| Return hotspots: Machines ×3.6, Tables ×2.9, Bookcases ×2.4, Appliances ×2.1, Copiers ×1.9, Phones ×1.6 | ✅ | `14_` RT-03 recovered **the exact rank order** of all six. My multipliers are compressed (Machines ×2.11 not ×3.6) because a return is recorded on an order that usually contains several categories, so each category's rate is diluted toward the base rate. Right ordering, understated magnitude, and I can explain why |
| Revenue growing while profit does not | ✅ | The headline. `10_` SP-02/SP-04 |
| No individual product loses money | ✅ | `11_` PP-03. Not listed as a planted signal but it is the structural consequence of the margin-cliff design, and it is what redirects the whole recommendation from "cut products" to "cap discounts" |
| **Weak cohort: customers acquired Apr–Sep 2020 repeat at 55% of normal** | ❌ | **Missed.** I grouped cohorts by acquisition *year*, which averages a six-month effect across twelve months and dilutes it below noticing. I saw later cohorts performing worse and attributed all of it to a shorter observation window — a reasonable explanation that happened to be wrong. Found only after opening the key: 54.8% of that cohort reordered against 77.0% for the six months before it. Query added as `12_` CA-03c, clearly marked as a post-key addition |

### Injected defects: **6 found of 7** (and the 7th is not in the file)

| Defect | Key says | I found | Verdict |
|---|---|---|---|
| `zero_sales_with_qty` | 4,002 | 4,002 | ✅ quarantined |
| `ship_before_order` | 2,501 | 2,501 | ✅ kept + flagged |
| `dup_row_id` | 2,501 | 2,502 rows sharing `row_id = '1'` | ✅ found; the key describes it as "reused across two orders", the file shows one value overwritten wholesale |
| `region_case` | 1,500 | ✅ | found together with the next one — 2,298 rows across 10 non-canonical spellings |
| `region_whitespace` | 800 | ✅ | as above (1,500 + 800 = 2,300 ≈ 2,298) |
| `thousands_separator` | 400 | **18** | ✅ found, and the gap is explained: only **4.48%** of sales values are ≥ 1,000, so a thousands comma is only *visible* on ~4.5% of the 400 rows it was applied to. 400 × 4.48% ≈ 18. The defect was injected 400 times and manifests 18 times |
| `customer_id_two_names` | 34 | **0** | **Not present in the delivered file.** `GROUP BY customer_id HAVING count(DISTINCT customer_name) > 1` returns zero rows out of 1,000,569. Either the injection did not take, or it was overwritten by a later step in the generator. I would rather report a disagreement with the key and show the query than claim a find I did not make |

### Found but never planted

The interesting column — things the generator was not told to produce:

1. **The margin decline is 62% "rate" and only 38% "mix".** Decomposing by discount band
   (`10_` SP-04b) splits the −8.39 pp fall into −3.20 pp from revenue moving into deeper discount
   bands and −5.19 pp from margin falling *within* bands. **−2.27 pp of it is on business sold at
   full price**, which no discount policy can touch. The generator planted discount creep and
   regional margin decay separately; that they compose into a 27%/73% split was not designed, and
   it is the thing that stops the recommendation from being one-sided.
2. **The West gap survives every obvious explanation.** Not product mix (identical across regions,
   and mix-adjusting moves West 0.03 pp). Not discount rate (within 0.4 pp of every region). It is
   visible on lines sold at zero discount. Three hypotheses killed before the fourth stuck.
3. **Acquisition collapsed 68% in 2021** — 38,683 new customers in 2019 → 12,301 in 2021, while
   revenue kept growing because existing customers ordered more (1.26 → 1.86 orders each). The
   growth story and the acquisition story point in opposite directions, and only one of them is
   in the board deck.
4. **Returns are flat and were never the problem.** 8.12% → 8.20% over four years, and net margin
   (21.77%) is *higher* than gross (21.62%). Finance's stated hypothesis, tested and not supported
   — which is a finding, not a dead end.
5. **The 0.85 discount band is anomalous.** 5,062 lines against 1,608 in the 0.80 band, growing
   from 17 lines in 2018 to 3,591 in 2021. A geometric decay that suddenly triples looks like an
   approval ceiling being used as a default rather than an exception.

### Score

**9 of 10 signals · 6 of 7 defects (7th disproved) · 5 emergent findings.**

The miss is a real one and the reason is specific: **I grouped at a coarser grain than the effect
I was hunting.** A six-month cohort effect cannot survive being averaged into a year, and the
result still looks plausible, which is what makes it dangerous. Group at the finest grain the data
supports, then aggregate up.

---

## Concepts that finally clicked

In my own words, not the primer's.

| Concept | My own one-line explanation |
|---|---|
| **Grain** | The sentence that finishes "one row of this table is exactly one ___". If I cannot finish it, I do not understand the table, and every number I compute from it is a guess |
| **Fan-out** | Joining a table to one at a finer grain silently copies its rows. Nothing errors. The row count goes up and every `SUM` goes up with it. Here: joining 27,674 returns to order *lines* gives 89,325 rows — a 3.23× inflation that turns an 8.19% return rate into 8.96% and reorders every category ranking |
| **Additivity** | `sales` adds up across anything. `discount` does not — it is a rate, and the sum of rates is nonsense. Rates get recomputed from their components at every level, never summed and never averaged |
| **Filter context** | The set of filters a DAX measure is evaluated under — from slicers, the visual's rows and columns, and the page. The same measure returns a different number in every cell of a matrix, and that is the feature, not a bug |
| **`CALCULATE`** | The only way to change filter context. By default it *replaces* filters on a column; `KEEPFILTERS` makes it *intersect* instead. That one word is the difference between "profit at 30%+ discount" ignoring your band slicer and respecting it |
| **Window function vs `GROUP BY`** | `GROUP BY` collapses rows and you lose the detail. A window function keeps every row and adds the aggregate beside it. Anything phrased as "…compared to its group" (rank, running total, share of parent, previous month) is a window function |
| **Ratio of sums vs sum of ratios** | `SUM(profit)/SUM(sales)` weights each line by its size. `AVG(profit/sales)` gives a $2 pencil the same vote as a $20,000 copier. They can differ by tens of points and only the first one is the margin |
| **Statistics vs indexes** | A slow query is not automatically a missing index. `ANALYZE` after a bulk load is what stops the planner assuming one row and choosing a nested loop — it took the model build from 10 minutes to 32 seconds, and no index was involved |
| **RLS vs OLS** | RLS hides *rows*, OLS hides *columns*. "Nobody outside Commercial should see customer names" is a column requirement, so RLS is the wrong tool no matter how confidently you configure it |

---

## If I did this again

1. **Profile the second and third sources on Day 1, not on Day 2.** I profiled `orders`
   thoroughly and glanced at `targets`. The targets file had ten spellings, mixed units, duplicates
   and a missing row — 45 minutes of Day 2 that should have been Day 1 work, discovered while I was
   supposed to be answering questions.
2. **Write the counterfactual bounds before the point estimate.** I built the naive number first
   and then had to think about what it assumed. Building the bounds first would have got me to the
   order-grain lower bound immediately instead of after a wrong version.
3. **Cohort at month grain from the start.** The one miss in the whole project came from choosing a
   bucket wider than the effect. It cost nothing extra to compute at month grain and roll up.
4. *(Bonus, because it cost the most time)* **`ANALYZE` immediately after every `CREATE TABLE AS`.**
   Ten minutes of build time and two cancelled runs, for a one-line fix I now cannot forget.
