# Question register

Derived on Day 0 from [`../STAKEHOLDER-BRIEF.md`](../STAKEHOLDER-BRIEF.md), then merged with
[`../_SEALED-question-list.md`](../_SEALED-question-list.md) after scoring.

**37 questions across 7 objectives.** 21 descriptive, 11 diagnostic, 5 decisions.

| Column | Meaning |
|---|---|
| **Type** | `D` descriptive (*what is the level?*) · `X` diagnostic (*why did it move?*) · `!` decision (*what do we do, and what is it worth?*) |
| **Approach** | How you will answer it — the method, not the filename |
| **Visual** | Page + visual that carries it |
| **Answer** | The headline number, written **the day you run the query** |

Two rules that make this file worth keeping:

- **A question with no query is a question you did not answer.**
- **A query with no visual is analysis nobody will see.**

The Answer column does double duty: it is the baseline your DAX gets checked against at the Day 3
gate, and the raw material for the Day 5 write-up.

---

## SP — Sales performance · `10_sales_performance.sql`

| ID | Question | Type | Approach | Visual | Answer |
|---|---|---|---|---|---|
| **SP-01** | How has monthly revenue changed compared with the same month last year? | D | Aggregate net revenue by month; calculate YoY % change. | P1 line + KPI cards |  Revenue grew every month of 2021 but decelerated hard: +47.0% YoY in Jan to **+0.5% in Dec**. Profit YoY turned negative in Jul and finished **-13.6% in Dec**. |
| **SP-02** | Are revenue growth rates accelerating, slowing, or reversing? | D | Monthly/quarterly growth rates; identify largest positive and negative swings. | P1 line |  Reversing. Revenue growth 121.7% -> 39.9% -> **11.8%**; profit growth 96.0% -> 23.9% -> **-1.3%**. |
| **SP-03** | How has profit changed month by month compared with revenue? | D | Revenue, profit and margin by month with YoY comparison. | P1 combo chart |  Rebased to Jan-2018 = 100, revenue reaches 1,743 by Dec-2021 while profit reaches only 1,213. Margin fell every year: 27.17 / 24.02 / 21.27 / **18.78%**. |
| **SP-04** | What explains the gap between strong revenue growth and weaker profit growth? | X | Decompose the profit gap into discount, returns, product mix and regional mix contributions. | P1 waterfall |  Two-factor bridge, 2021: profit fell **$190,962**. Growth *added* **+$1,734,127**; the margin rate *destroyed* **-$1,925,089**. Residual exactly 0. |
| **SP-05** | Which months, products or categories contributed most to the margin decline? | X | Contribution-to-change analysis by month/product/category, in percentage points and dollars. | P1 ranked bar |  Machines **-$260,611** (136.5% of the total change), Tables **-$178,887**, Bookcases -$76,221, Chairs -$48,428, Supplies -$33,825. By month, December alone lost **$233,576**. |
| **SP-06** | What are total revenue, order volume, units and profit — overall and per year? | D | Straight aggregation at order and line grain. Establishes the baseline every other question compares against. | P1 KPI row |  **$218,617,012.65** revenue - **$47,254,458.39** profit - **21.62%** margin - 337,737 orders - 996,567 lines - 3,338,886 units - 107,688 customers. |
| **SP-07** | Which calendar months run above or below a typical month, averaged across all four years? | D | Average each calendar month **across** years, then index against the grand monthly mean. Not a ranking of all 48 months — that only finds the biggest year. | P1 seasonality bar |  Dec **135.5**, Nov 133.9, Sep 124.5, Oct 110.7 against a typical month = 100. Trough Jan **64.3**, Feb 65.6. Q4 runs ~35% above a typical month. |
| **SP-08** | What is average order value, and how has it moved year over year? | D | Collapse line grain to **order** grain in a CTE first, then average. Report median alongside the mean. | P1 KPI |  AOV **$647.30** overall; falling **$680.83 -> $627.92** (-7.8%) 2018-21. Median $323.80 -> $298.13. Lines per order flat at 2.95, so this is price, not basket size. |

## PP — Product performance · `11_product_performance.sql`

| ID | Question | Type | Approach | Visual | Answer |
|---|---|---|---|---|---|
| **PP-01** | Which products and categories generate the most revenue? | D | Aggregate net revenue by product and category; rank descending. | P2 bar + table |  Technology **$95.3M** (43.6%), Office Supplies $62.8M (28.7%), Furniture $60.6M (27.7%). Top sub-categories: Phones $34.3M, Machines $32.8M, Chairs $21.5M. |
| **PP-02** | Which products generate the most profit and the highest margin? | D | Profit and margin by product. Margin = SUM(profit)/SUM(sales), never an average of row ratios. | P2 scatter + table |  Highest margins: Paper 39.58%, Binders 39.39%, Labels 38.45%, Envelopes 38.14%, Copiers 36.28%. Top product by profit: Canon imageCLASS 2200 Copier, **$2.14M**. |
| **PP-03** | Which products or categories are losing money? | D | Contribution profit and margin by product/category; filter negatives. | P2 bar |  **Zero of 1,862 products lose money overall.** The losses live in discount *bands*, not in products - the single most important finding on this page. |
| **PP-04** | Is the furniture category actually dragging profitability, as Sales believes? | X | Furniture vs other categories on revenue, profit, margin and YoY change. Tests a stakeholder's stated hypothesis. | P2 comparison + waterfall |  **No.** Furniture is a level problem, not the cause. Margin excluding Furniture fell 30.77% -> 22.32% (**-8.45 pp**) against -8.39 pp including it. Removing Furniture changes the trajectory by 0.06 pp. |
| **PP-05** | Which categories have deteriorated most in margin year over year? | X | Current vs prior-year margin by category, in percentage points. | P2 ranked bar |  Machines **-16.12 pp**, Tables -11.99, Bookcases -10.52 (2018 vs 2021). Every one of the 17 sub-categories fell; the smallest fall was -5.76 pp. |
| **PP-06** | Which products combine high sales with weak margins? | X | Revenue contribution vs margin. Define "high" and "low" from **quartiles of the data**, not an invented threshold. | P2 scatter, lower-right quadrant |  647 products sit above median revenue and below median margin. They carry **$155.0M of revenue at 16.62% margin** and average **12.0% discount** against 10.3% elsewhere. |
| **PP-07** | Which sub-categories are below-threshold on margin in a **majority of months**, as distinct from worst-on-average? | X | Count periods below threshold per sub-category — not an average. An average hides a line that is fine for 10 months and catastrophic for 2; those need different fixes. State the threshold explicitly. | P2 heat table |  Seven sub-categories are below the company margin in **48 of 48 months**: Tables, Chairs, Bookcases, Appliances, Storage, Supplies, Phones. Tables was *negative* in 9 of 48. |
| **PP-08** | What share of products generates 80% of revenue? | D | Rank products by revenue; cumulative sum over the ranked list divided by the grand total. | P2 Pareto |  **468 of 1,862 products (25.1%)** generate 80% of revenue. The top 100 alone make 39.6%. |

## CA — Customer analytics · `12_customer_analytics.sql`

| ID | Question | Type | Approach | Visual | Answer |
|---|---|---|---|---|---|
| **CA-01** | Who are our highest-value customers? | D | Revenue and profit by customer, ranked. | P3 ranked table + drill-through |  Top customer $42,075 lifetime over 9 orders. The top 20 range $30.9k-$42.1k. Shown with masked names per the Day 3 Legal request. |
| **CA-02** | How concentrated is revenue and profit among our largest customers? | D | Cumulative contribution from the top 10%, 20% and 50% of customers. | P3 Pareto |  Top 1% of customers = **7.8%** of revenue - top 10% = **38.1%** - top 20% = 57.3% - top 50% = 87.7%. |
| **CA-03** | Are we retaining our valuable customers? | X | Repeat rate and cohort retention by first-purchase month × months-since. Month 0 must be 100% for every cohort — that is the correctness check. | P3 cohort heatmap + line |  Repeat rate **72.4%**; repeat customers generate **91.0%** of revenue. Cohort m0 = 100.0% for all 48 cohorts (correctness check passed). Acquisition collapsed: 38,683 new customers in 2019 -> **12,301 in 2021**. |
| **CA-04** | Which high-value customers have stopped buying or are spending materially less? | **!** | Compare historical vs recent spend per customer; produce a ranked win-back list with decline %. RFM scoring via `NTILE(5)`; recency inverts. | P3 ranked table |  **9,468 customers** classed AT RISK - high value, holding **$32.9M lifetime revenue** and **$8.1M lifetime profit**, quiet for an average of **594 days**. |
| **CA-05** | How many unique and active customers do we have, and what does the order-frequency distribution look like? | D | Distinct customer counts overall and per year; distribution of orders per customer. Use a **fixed** as-of date, never `current_date`. | P3 KPI + frequency histogram |  107,688 customers ever, 3.14 orders each, $2,030 revenue each. 27.6% ordered once; 13.7% ordered 6+ times. Orders per active customer rose 1.26 -> **1.86**. |

## RP — Regional performance · `13_regional_performance.sql`

| ID | Question | Type | Approach | Visual | Answer |
|---|---|---|---|---|---|
| **RP-01** | How do regions compare on revenue, profit, margin and growth? | D | Aggregate all four by region, with YoY growth. Drill to state and city. | P3 map + scorecard |  West $77.3M (35.4% of revenue, 30.3% of profit, **18.55% margin**) - East $61.2M (23.31%) - Central $45.4M (22.29%) - South $34.7M (**24.57%**). No state loses money. |
| **RP-02** | Is West genuinely under-resourced relative to its sales and profit opportunity? | **!** | West vs other regions on revenue, growth, margin trajectory and available resource measures. Produces an evidence-based yes/no with a quantified gap. | P3 regional comparison |  **No - not on any measure in the data.** West has the *highest* revenue per customer ($2,249) and orders per customer (3.49), and its discount rate is within 0.4 pp of every region. Its margin on **full-price** lines fell 33.34% -> **24.70%** while South's was flat. A pricing / cost-to-serve issue, not headcount. |
| **RP-03** | Which regions are out- or under-performing the company overall? | D | Each region's growth against the company benchmark. | P3 variance bar |  West grew 311.1% vs the company's 246.7% (+64.4 pp) but sits **-4.39 pp** below company margin. South grew slowest (169.2%) and is **+4.55 pp** above. |
| **RP-04** | Which regions contribute most to the overall profit decline or improvement? | X | Contribution-to-change in total profit by region. | P3 waterfall |  West alone is **199.6%** of the 2020-21 company profit change: **-$381,102** against a company total of -$190,962. Every other region was positive or flat. |

## RT — Returns · `14_returns_analysis.sql`

| ID | Question | Type | Approach | Visual | Answer |
|---|---|---|---|---|---|
| **RT-01** | What is the return rate, and how much revenue and profit do returned orders represent? | D | Returned orders and associated revenue/profit at the **correct order grain**. Returns are order-grain, orders are line-grain — aggregate before joining, or use `EXISTS`. | P4 KPI cards + trend |  Return rate **8.19%** (27,674 of 337,737 orders). Returned orders carry **$23.2M revenue** (10.62%) and **$4.72M profit**. |
| **RT-02** | Is the return rate increasing or decreasing over time? | D | Monthly/quarterly return rate with YoY change. | P4 line |  **Flat.** 8.12% (2018) - 8.24% - 8.18% - **8.20%** (2021). Finance's "returns are eating us alive" is not supported by the trend. |
| **RT-03** | Which products, categories and regions have the highest return rates? | D | Return rate by product, category and region. Sanity-check each against the overall rate — a category rate far above it means a fan-out. | P4 ranked bars |  Machines **17.32%**, Tables 13.99%, Bookcases 11.84%, Appliances 10.64%, Copiers 10.37% against the 8.19% base. By region the spread is under 0.5 pp - returns are a product problem, not a regional one. |
| **RT-04** | How much profit is lost annually because of returns? | X | Annual profit impact attributable to returned orders, gross → returns → net. | P4 waterfall |  Profit booked on returned orders: $4.72M over four years, **$1.49M in 2021**. Net margin (21.77%) is *higher* than gross (21.62%), so returns are marginally dilutive, not the cause of the decline. |
| **RT-05** | Are our highest-return sub-categories also our top sellers, and what is net contribution after returns? | X | Overlap of return-rate rank against revenue rank. High return on a low seller is a nuisance; on a top seller it is a strategy problem. | P4 overlap table |  Yes - Machines is **revenue rank 2** and **return-rate rank 1**; Phones is rank 1 on revenue and rank 6 on returns. High returns sitting on top sellers is a strategy problem, not a nuisance. |

## DP — Discounting & pricing · `11_product_performance.sql`

> Not in the sealed list — derived from Finance's forwarded note. This group carries the project's
> central finding. `DP-03` and `DP-04` feed `16_discount_counterfactual.sql` on Day 3.

| ID | Question | Type | Approach | Visual | Answer |
|---|---|---|---|---|---|
| **DP-01** | How much discounting is happening, and has the discount rate risen over time? | D | Mean discount %, total discount dollars, and trend by month/quarter/year. | P1 line + KPI cards |  Weighted discount rose **7.28% -> 14.89%**; discount dollars **$1.75M -> $13.55M**; share of lines at 50%+ discount **0.6% -> 5.9%**. Total given away over four years: **$30.3M**. |
| **DP-02** | Which products, categories and discount bands are associated with low or negative margins? | X | Band the discount (5-point buckets), compute margin per band per sub-category. Require a minimum band size or thin bands flip on noise. | P1 heatmap + bar |  Margin by band: 0% **30.74%** - 1-9% 26.59% - 10-19% 19.23% - 20-29% 8.61% - 30-39% **-3.47%** - 40-49% -17.13% - 50-59% -32.07% - 80-89% -87.53%. Company break-even sits between the 20-29% and 30-39% bands. |
| **DP-03** | Are orders discounted at 50%+ actually losing money, and what does that cost annually? | **!** | Filter to 50%+ discounts; order count, revenue, profit/loss, annualised. Answers Finance's question literally, with a number. | P1 KPI + table |  **Yes.** 36,935 lines across 34,597 orders, $4.60M revenue, **-$2.11M profit** (-45.82% margin), $8.60M given away. 2021 alone: **-$1.22M**, growing from -$9.5k in 2018. |
| **DP-04** | At what discount level does additional discounting destroy profitability, by sub-category? | **!** | Margin across discount bands; find where the sign flips using `LAG` over the bands. The answer is the threshold you set policy at. | P1 line with zero reference |  Break-even discount by sub-category ranges from **10% (Tables)** to **60% (Binders, Paper)**: Bookcases 15 - Machines/Supplies 20 - Appliances/Chairs/Copiers/Storage 30 - Phones 35 - Accessories/Art 40 - Fasteners/Furnishings 45 - Envelopes 50 - Labels 55. **One company-wide cap is the wrong instrument.** |

## TA — Targets vs actuals · `15_targets.sql`

> Not in the sealed list — derived from Sales' forwarded note about Bhavna's target sheet.

| ID | Question | Type | Approach | Visual | Answer |
|---|---|---|---|---|---|
| **TA-01** | How did each region perform against its annual revenue target? | D | Join targets to actuals via an explicit crosswalk; variance in dollars and %. `FULL OUTER JOIN` so gaps on both sides surface. | P3 target vs actual bar |  2021: East 107.7% - South 107.3% - Central 96.3% - **West 93.7% (-$1.94M)**. Across all years East attained 97.4%, West 100.7%, South 100.9%, Central 104.5%. |
| **TA-02** | Which regions are materially above or below target? | D | Attainment % by region-year; filter to material variances. | P3 variance bar |  East missed 3 of 4 years; West missed 2 of 4 including 2021 by the largest absolute amount. South met 3 of 4. |
| **TA-03** | Are the regional targets reliable enough to use for performance decisions at all? | **!** | Reconcile the target file for missing region-years, inconsistent region spellings, mixed units and duplicates. The answer determines whether TA-01/02 can be shown to the board. | P3 data-quality panel |  **Usable, with caveats stated on the visual.** 17 rows, **10 spellings** of 4 regions, 3 rows recorded in thousands flagged only by a `Units` column, 2 exact duplicates, and **no target at all for Central 2018** - left missing, not estimated. |

---

## Coverage check

| Objective | Questions | `D` | `X` | `!` | Day | Query |
|---|---|---|---|---|---|---|
| SP Sales performance | 8 | 6 | 2 | 0 | 2 | `10_` |
| PP Product performance | 8 | 4 | 4 | 0 | 2 | `11_` |
| CA Customer analytics | 5 | 3 | 1 | 1 | 2 | `12_` |
| RP Regional performance | 4 | 2 | 1 | 1 | 2 | `13_` |
| RT Returns | 5 | 3 | 2 | 0 | 2 | `14_` |
| DP Discounting & pricing | 4 | 1 | 1 | 2 | 2 | `11_`, `16_` |
| TA Targets vs actuals | 3 | 2 | 0 | 1 | 2 | `15_` |
| **Total** | **37** | **21** | **11** | **5** | | |

## Roll-up to the three management questions

1. **What is happening?** — SP-01, SP-02, SP-03, SP-06, SP-07, SP-08, PP-01, PP-02, PP-03, PP-08,
   CA-01, CA-02, CA-05, RP-01, RP-03, RT-01, RT-02, RT-03, DP-01, TA-01, TA-02
2. **Why is it happening?** — SP-04, SP-05, PP-04, PP-05, PP-06, PP-07, CA-03, RP-04, RT-04,
   RT-05, DP-02
3. **What should the business do?** — CA-04, RP-02, DP-03, DP-04, TA-03

---

## Day 0 scoring — against the sealed list

**17 of 25 matched** (15 clean, 2 partial) · **8 missed** · **7 added**

| Missed | Now covered by |
|---|---|
| Total revenue, volume, profit | SP-06 |
| Average order value | SP-08 |
| Seasonality by calendar month | SP-07 |
| Consistently underperforming products | PP-07 |
| Product Pareto (% of revenue from top products) | PP-08 |
| Active and unique customer counts | CA-05 |
| Average customer order frequency | CA-05 |
| High-return products that are also top sellers | RT-05 |

**The pattern in the misses:** every originally-derived question was *comparative* — a change, a
ranking, a gap. None established a baseline magnitude. Page 1 needs a KPI row, and Priya needs
"how are we doing" before "why is it happening". The probe that was missing is the simplest one:
**what is the total?**

**Added beyond the sealed list:** the whole `DP` group (4) and the whole `TA` group (3). The
sealed list has no discount analysis and no targets analysis — and `DP-04` is the question that
becomes this project's headline recommendation. `TA-03` elevates a data-quality check into a
business question, which is the more senior move.
