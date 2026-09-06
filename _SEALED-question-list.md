# Question register

Every business question gets an ID, a query that answers it, and a place on the dashboard.
Fill the last two columns as you build — a question with no query is a question you did not answer,
and a query with no visual is analysis nobody will see.

**Answer** = the headline number, written the day you run the query.

## Sales performance

| ID | Question | Query | Visual | Answer |
|---|---|---|---|---|
| SP1 | Total revenue, sales volume and profit? | `10_sales_performance.sql` | P1 KPI row | |
| SP2 | How are revenue and profit changing over time? | `10_` | P1 trend line | |
| SP3 | Which months/quarters generate the highest sales? | `10_` | P1 seasonality bar | |
| SP4 | What is the average order value? | `10_` | P1 KPI | |
| SP5 | Major contributors to revenue growth/decline? | `10_` | P1 YoY breakdown | |

## Product performance

| ID | Question | Query | Visual | Answer |
|---|---|---|---|---|
| PP1 | Which products and categories generate the highest revenue? | `11_product_performance.sql` | P2 matrix | |
| PP2 | Which products generate the highest profit? | `11_` | P2 top-N table | |
| PP3 | Which products have high sales but low profitability? | `11_` | P2 scatter, lower-right quadrant | |
| PP4 | Which products consistently underperform? | `11_` | P2 underperformer table | |
| PP5 | What % of revenue comes from the top products? | `11_` | P2 Pareto | |

## Customer analytics

| ID | Question | Query | Visual | Answer |
|---|---|---|---|---|
| CA1 | How many active and unique customers? | `12_customer_analytics.sql` | P3 KPI | |
| CA2 | What % of customers repeat-purchase? | `12_` | P3 repeat vs one-time | |
| CA3 | Average customer order frequency? | `12_` | P3 frequency histogram | |
| CA4 | Which customers contribute the most revenue? | `12_` | P3 top-N + drill-through | |
| CA5 | Which segments have the highest lifetime value? | `12_` (RFM) | P3 segment breakdown | |
| CA6 | Which segments show declining activity? | `12_` (cohort) | P3 retention matrix | |

## Regional performance

| ID | Question | Query | Visual | Answer |
|---|---|---|---|---|
| RP1 | Which regions/states/cities generate the highest revenue? | `13_regional_performance.sql` | P4 map | |
| RP2 | Which regions have the highest profit margins? | `13_` | P4 margin bar | |
| RP3 | Which regions have high sales but low profitability? | `13_` | P4 quadrant | |
| RP4 | Where are customer and order volumes growing or declining? | `13_` | P4 growth table | |

## Returns

| ID | Question | Query | Visual | Answer |
|---|---|---|---|---|
| RT1 | What is the overall return rate? | `14_returns_analysis.sql` | P1 + P4 KPI | |
| RT2 | Which products/categories have the highest return rates? | `14_` | P4 return-rate bar | |
| RT3 | Which regions experience the most returns? | `14_` | P4 map overlay | |
| RT4 | How do returns affect revenue and profitability? | `14_` | P4 waterfall | |
| RT5 | Are high-return products also top sellers? | `14_` | P4 overlap table | |
