-- =============================================================================
-- 13_regional_performance.sql - Regional performance (register IDs RP-01..RP-04)
-- =============================================================================
-- Priya's email has a live political question in it: "West has been loud about
-- being under-resourced." RP-02 answers that with evidence rather than with a
-- shrug, and the answer has to survive being read by the person it is about.
-- =============================================================================

\pset pager off


-- =============================================================================
-- RP-01 - How do regions compare on revenue, profit, margin and growth?
-- approach: all four measures side by side, plus the 2018->2021 CAGR, so a
--           region that is big and a region that is growing are visibly
--           different things.
-- =============================================================================

SELECT
    g.region,
    count(DISTINCT f.order_id)                                     AS orders,
    count(DISTINCT f.customer_key)                                 AS customers,
    sum(f.sales)::numeric(14,2)                                    AS revenue,
    round(100.0 * sum(f.sales) / sum(sum(f.sales)) OVER (), 1)     AS pct_of_revenue,
    sum(f.profit)::numeric(14,2)                                   AS profit,
    round(100.0 * sum(f.profit) / sum(sum(f.profit)) OVER (), 1)   AS pct_of_profit,
    round(100.0 * sum(f.profit) / sum(f.sales), 2)                 AS margin_pct,
    round(100.0 * avg(f.discount), 2)                              AS avg_discount_pct,
    round(sum(f.sales) / count(DISTINCT f.order_id), 2)            AS aov
FROM core.fact_order_line f
JOIN core.dim_geography g ON g.geography_key = f.geography_key
GROUP BY g.region
ORDER BY revenue DESC;

-- By region and year, with growth and margin trajectory.
WITH ry AS (
    SELECT g.region, d.year,
           sum(f.sales)  AS revenue,
           sum(f.profit) AS profit
    FROM core.fact_order_line f
    JOIN core.dim_geography g ON g.geography_key = f.geography_key
    JOIN core.dim_date      d ON d.date_key      = f.date_key
    GROUP BY g.region, d.year
)
SELECT region, year,
       revenue::numeric(14,2)                                          AS revenue,
       round(100.0 * (revenue - lag(revenue) OVER (PARTITION BY region ORDER BY year))
                   / nullif(lag(revenue) OVER (PARTITION BY region ORDER BY year), 0), 1)
                                                                       AS revenue_growth_pct,
       profit::numeric(14,2)                                           AS profit,
       round(100.0 * profit / revenue, 2)                              AS margin_pct,
       round(100.0 * profit / revenue
           - lag(100.0 * profit / revenue) OVER (PARTITION BY region ORDER BY year), 2)
                                                                       AS margin_change_pp
FROM ry
ORDER BY region, year;

-- Top 10 states, for the map drill-down.
SELECT g.state, g.region,
       sum(f.sales)::numeric(14,2)                    AS revenue,
       sum(f.profit)::numeric(14,2)                   AS profit,
       round(100.0 * sum(f.profit) / sum(f.sales), 2) AS margin_pct
FROM core.fact_order_line f
JOIN core.dim_geography g ON g.geography_key = f.geography_key
GROUP BY g.state, g.region
ORDER BY revenue DESC
LIMIT 10;

-- The states that lose money, if any. A negative state inside a positive
-- region is the sort of thing a regional average hides.
SELECT g.state, g.region,
       sum(f.sales)::numeric(14,2)                    AS revenue,
       sum(f.profit)::numeric(14,2)                   AS profit,
       round(100.0 * sum(f.profit) / sum(f.sales), 2) AS margin_pct
FROM core.fact_order_line f
JOIN core.dim_geography g ON g.geography_key = f.geography_key
GROUP BY g.state, g.region
HAVING sum(f.profit) < 0
ORDER BY profit;


-- =============================================================================
-- RP-02 - Is West genuinely under-resourced?  *** decision question ***
-- approach: "under-resourced" is not a column, so it has to be operationalised.
--           I read it as: West carries a disproportionate share of the
--           business relative to the coverage it gets. Three observable
--           proxies for coverage, all of which are in the data:
--             - revenue per active customer   (are reps spread thin?)
--             - orders per customer           (repeat servicing)
--             - discount rate                 (are they discounting to close
--                                              because they cannot service?)
--           Then the share test: revenue share vs customer share vs profit
--           share. A region generating 36% of revenue on 34% of customers is
--           not under-resourced in any sense the data can see; one whose
--           discount rate is 3 points above everyone else's is being asked to
--           buy its way to the number.
--
--           Stating the proxy explicitly is the point. The wrong answer here
--           is a confident yes/no with no definition attached.
-- =============================================================================

WITH r AS (
    SELECT g.region,
           count(DISTINCT f.customer_key)  AS customers,
           count(DISTINCT f.order_id)      AS orders,
           sum(f.sales)                    AS revenue,
           sum(f.profit)                   AS profit,
           avg(f.discount)                 AS avg_discount
    FROM core.fact_order_line f
    JOIN core.dim_geography g ON g.geography_key = f.geography_key
    GROUP BY g.region
)
SELECT
    region,
    round(100.0 * revenue   / sum(revenue)   OVER (), 1)      AS pct_of_revenue,
    round(100.0 * profit    / sum(profit)    OVER (), 1)      AS pct_of_profit,
    round(100.0 * customers / sum(customers) OVER (), 1)      AS pct_of_customers,
    round(100.0 * orders    / sum(orders)    OVER (), 1)      AS pct_of_orders,
    round(revenue / customers, 2)                             AS revenue_per_customer,
    round(orders::numeric / customers, 2)                     AS orders_per_customer,
    round(100.0 * avg_discount, 2)                            AS avg_discount_pct,
    round(100.0 * profit / revenue, 2)                        AS margin_pct,
    -- The gap that matters: revenue share minus profit share. Positive means
    -- the region brings in more revenue than profit - it is working harder for
    -- less, which is the measurable half of "under-resourced".
    round(100.0 * revenue / sum(revenue) OVER ()
        - 100.0 * profit  / sum(profit)  OVER (), 1)          AS revenue_minus_profit_share_pp
FROM r
ORDER BY pct_of_revenue DESC;


-- =============================================================================
-- RP-03 - Which regions out- or under-perform the company overall?
-- approach: each region's growth and margin measured as a variance against the
--           company benchmark, so "good" is relative to the company rather
--           than to zero.
-- =============================================================================

WITH ry AS (
    SELECT g.region, d.year, sum(f.sales) AS revenue, sum(f.profit) AS profit
    FROM core.fact_order_line f
    JOIN core.dim_geography g ON g.geography_key = f.geography_key
    JOIN core.dim_date      d ON d.date_key      = f.date_key
    GROUP BY g.region, d.year
),
company AS (
    SELECT year, sum(revenue) AS revenue, sum(profit) AS profit FROM ry GROUP BY year
),
growth AS (
    SELECT r.region,
           max(r.revenue) FILTER (WHERE r.year = 2018) AS rev_2018,
           max(r.revenue) FILTER (WHERE r.year = 2021) AS rev_2021,
           max(r.profit)  FILTER (WHERE r.year = 2018) AS pro_2018,
           max(r.profit)  FILTER (WHERE r.year = 2021) AS pro_2021
    FROM ry r GROUP BY r.region
),
co AS (
    SELECT max(revenue) FILTER (WHERE year = 2018) AS rev_2018,
           max(revenue) FILTER (WHERE year = 2021) AS rev_2021,
           max(profit)  FILTER (WHERE year = 2018) AS pro_2018,
           max(profit)  FILTER (WHERE year = 2021) AS pro_2021
    FROM company
)
SELECT
    g.region,
    round(100.0 * (g.rev_2021 / g.rev_2018 - 1), 1)                     AS revenue_growth_18_21_pct,
    round(100.0 * (c.rev_2021 / c.rev_2018 - 1), 1)                     AS company_growth_pct,
    round(100.0 * (g.rev_2021 / g.rev_2018 - 1)
        - 100.0 * (c.rev_2021 / c.rev_2018 - 1), 1)                     AS growth_vs_company_pp,
    round(100.0 * g.pro_2021 / g.rev_2021, 2)                           AS margin_2021_pct,
    round(100.0 * c.pro_2021 / c.rev_2021, 2)                           AS company_margin_2021_pct,
    round(100.0 * g.pro_2021 / g.rev_2021
        - 100.0 * c.pro_2021 / c.rev_2021, 2)                           AS margin_vs_company_pp
FROM growth g CROSS JOIN co c
ORDER BY growth_vs_company_pp DESC;


-- =============================================================================
-- RP-04 - Which regions contributed most to the profit change?
-- approach: contribution-to-change for 2020->2021, the year profit fell. Each
--           region's profit delta as a share of the company's total delta.
-- =============================================================================

WITH ry AS (
    SELECT g.region, d.year, sum(f.sales) AS revenue, sum(f.profit) AS profit
    FROM core.fact_order_line f
    JOIN core.dim_geography g ON g.geography_key = f.geography_key
    JOIN core.dim_date      d ON d.date_key      = f.date_key
    WHERE d.year IN (2020, 2021)
    GROUP BY g.region, d.year
),
p AS (
    SELECT region,
           max(revenue) FILTER (WHERE year = 2020) AS rev_2020,
           max(revenue) FILTER (WHERE year = 2021) AS rev_2021,
           max(profit)  FILTER (WHERE year = 2020) AS pro_2020,
           max(profit)  FILTER (WHERE year = 2021) AS pro_2021
    FROM ry GROUP BY region
)
SELECT
    region,
    (rev_2021 - rev_2020)::numeric(14,2)                             AS revenue_change,
    (pro_2021 - pro_2020)::numeric(14,2)                             AS profit_change,
    round(100.0 * (pro_2021 - pro_2020)
        / nullif(sum(pro_2021 - pro_2020) OVER (), 0), 1)            AS pct_of_company_profit_change,
    round(100.0 * pro_2021 / rev_2021 - 100.0 * pro_2020 / rev_2020, 2) AS margin_change_pp
FROM p
ORDER BY profit_change;
