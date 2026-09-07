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
| **SP-01** | How has monthly revenue changed compared with the same month last year? | D | Aggregate net revenue by month; calculate YoY % change. | P1 line + KPI cards | |
| **SP-02** | Are revenue growth rates accelerating, slowing, or reversing? | D | Monthly/quarterly growth rates; identify largest positive and negative swings. | P1 line | |
| **SP-03** | How has profit changed month by month compared with revenue? | D | Revenue, profit and margin by month with YoY comparison. | P1 combo chart | |
| **SP-04** | What explains the gap between strong revenue growth and weaker profit growth? | X | Decompose the profit gap into discount, returns, product mix and regional mix contributions. | P1 waterfall | |
| **SP-05** | Which months, products or categories contributed most to the margin decline? | X | Contribution-to-change analysis by month/product/category, in percentage points and dollars. | P1 ranked bar | |
| **SP-06** | What are total revenue, order volume, units and profit — overall and per year? | D | Straight aggregation at order and line grain. Establishes the baseline every other question compares against. | P1 KPI row | |
| **SP-07** | Which calendar months run above or below a typical month, averaged across all four years? | D | Average each calendar month **across** years, then index against the grand monthly mean. Not a ranking of all 48 months — that only finds the biggest year. | P1 seasonality bar | |
| **SP-08** | What is average order value, and how has it moved year over year? | D | Collapse line grain to **order** grain in a CTE first, then average. Report median alongside the mean. | P1 KPI | |

## PP — Product performance · `11_product_performance.sql`

| ID | Question | Type | Approach | Visual | Answer |
|---|---|---|---|---|---|
| **PP-01** | Which products and categories generate the most revenue? | D | Aggregate net revenue by product and category; rank descending. | P2 bar + table | |
| **PP-02** | Which products generate the most profit and the highest margin? | D | Profit and margin by product. Margin = SUM(profit)/SUM(sales), never an average of row ratios. | P2 scatter + table | |
| **PP-03** | Which products or categories are losing money? | D | Contribution profit and margin by product/category; filter negatives. | P2 bar | |
| **PP-04** | Is the furniture category actually dragging profitability, as Sales believes? | X | Furniture vs other categories on revenue, profit, margin and YoY change. Tests a stakeholder's stated hypothesis. | P2 comparison + waterfall | |
| **PP-05** | Which categories have deteriorated most in margin year over year? | X | Current vs prior-year margin by category, in percentage points. | P2 ranked bar | |
| **PP-06** | Which products combine high sales with weak margins? | X | Revenue contribution vs margin. Define "high" and "low" from **quartiles of the data**, not an invented threshold. | P2 scatter, lower-right quadrant | |
| **PP-07** | Which sub-categories are below-threshold on margin in a **majority of months**, as distinct from worst-on-average? | X | Count periods below threshold per sub-category — not an average. An average hides a line that is fine for 10 months and catastrophic for 2; those need different fixes. State the threshold explicitly. | P2 heat table | |
| **PP-08** | What share of products generates 80% of revenue? | D | Rank products by revenue; cumulative sum over the ranked list divided by the grand total. | P2 Pareto | |

## CA — Customer analytics · `12_customer_analytics.sql`

| ID | Question | Type | Approach | Visual | Answer |
|---|---|---|---|---|---|
| **CA-01** | Who are our highest-value customers? | D | Revenue and profit by customer, ranked. | P3 ranked table + drill-through | |
| **CA-02** | How concentrated is revenue and profit among our largest customers? | D | Cumulative contribution from the top 10%, 20% and 50% of customers. | P3 Pareto | |
| **CA-03** | Are we retaining our valuable customers? | X | Repeat rate and cohort retention by first-purchase month × months-since. Month 0 must be 100% for every cohort — that is the correctness check. | P3 cohort heatmap + line | |
| **CA-04** | Which high-value customers have stopped buying or are spending materially less? | **!** | Compare historical vs recent spend per customer; produce a ranked win-back list with decline %. RFM scoring via `NTILE(5)`; recency inverts. | P3 ranked table | |
| **CA-05** | How many unique and active customers do we have, and what does the order-frequency distribution look like? | D | Distinct customer counts overall and per year; distribution of orders per customer. Use a **fixed** as-of date, never `current_date`. | P3 KPI + frequency histogram | |

## RP — Regional performance · `13_regional_performance.sql`

| ID | Question | Type | Approach | Visual | Answer |
|---|---|---|---|---|---|
| **RP-01** | How do regions compare on revenue, profit, margin and growth? | D | Aggregate all four by region, with YoY growth. Drill to state and city. | P3 map + scorecard | |
| **RP-02** | Is West genuinely under-resourced relative to its sales and profit opportunity? | **!** | West vs other regions on revenue, growth, margin trajectory and available resource measures. Produces an evidence-based yes/no with a quantified gap. | P3 regional comparison | |
| **RP-03** | Which regions are out- or under-performing the company overall? | D | Each region's growth against the company benchmark. | P3 variance bar | |
| **RP-04** | Which regions contribute most to the overall profit decline or improvement? | X | Contribution-to-change in total profit by region. | P3 waterfall | |

## RT — Returns · `14_returns_analysis.sql`

| ID | Question | Type | Approach | Visual | Answer |
|---|---|---|---|---|---|
| **RT-01** | What is the return rate, and how much revenue and profit do returned orders represent? | D | Returned orders and associated revenue/profit at the **correct order grain**. Returns are order-grain, orders are line-grain — aggregate before joining, or use `EXISTS`. | P4 KPI cards + trend | |
| **RT-02** | Is the return rate increasing or decreasing over time? | D | Monthly/quarterly return rate with YoY change. | P4 line | |
| **RT-03** | Which products, categories and regions have the highest return rates? | D | Return rate by product, category and region. Sanity-check each against the overall rate — a category rate far above it means a fan-out. | P4 ranked bars | |
| **RT-04** | How much profit is lost annually because of returns? | X | Annual profit impact attributable to returned orders, gross → returns → net. | P4 waterfall | |
| **RT-05** | Are our highest-return sub-categories also our top sellers, and what is net contribution after returns? | X | Overlap of return-rate rank against revenue rank. High return on a low seller is a nuisance; on a top seller it is a strategy problem. | P4 overlap table | |

## DP — Discounting & pricing · `11_product_performance.sql`

> Not in the sealed list — derived from Finance's forwarded note. This group carries the project's
> central finding. `DP-03` and `DP-04` feed `16_discount_counterfactual.sql` on Day 3.

| ID | Question | Type | Approach | Visual | Answer |
|---|---|---|---|---|---|
| **DP-01** | How much discounting is happening, and has the discount rate risen over time? | D | Mean discount %, total discount dollars, and trend by month/quarter/year. | P1 line + KPI cards | |
| **DP-02** | Which products, categories and discount bands are associated with low or negative margins? | X | Band the discount (5-point buckets), compute margin per band per sub-category. Require a minimum band size or thin bands flip on noise. | P1 heatmap + bar | |
| **DP-03** | Are orders discounted at 50%+ actually losing money, and what does that cost annually? | **!** | Filter to 50%+ discounts; order count, revenue, profit/loss, annualised. Answers Finance's question literally, with a number. | P1 KPI + table | |
| **DP-04** | At what discount level does additional discounting destroy profitability, by sub-category? | **!** | Margin across discount bands; find where the sign flips using `LAG` over the bands. The answer is the threshold you set policy at. | P1 line with zero reference | |

## TA — Targets vs actuals · `15_targets.sql`

> Not in the sealed list — derived from Sales' forwarded note about Bhavna's target sheet.

| ID | Question | Type | Approach | Visual | Answer |
|---|---|---|---|---|---|
| **TA-01** | How did each region perform against its annual revenue target? | D | Join targets to actuals via an explicit crosswalk; variance in dollars and %. `FULL OUTER JOIN` so gaps on both sides surface. | P3 target vs actual bar | |
| **TA-02** | Which regions are materially above or below target? | D | Attainment % by region-year; filter to material variances. | P3 variance bar | |
| **TA-03** | Are the regional targets reliable enough to use for performance decisions at all? | **!** | Reconcile the target file for missing region-years, inconsistent region spellings, mixed units and duplicates. The answer determines whether TA-01/02 can be shown to the board. | P3 data-quality panel | |

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
