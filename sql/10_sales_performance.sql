-- =============================================================================
-- 10_sales_performance.sql - Sales performance  (register IDs SP-01 .. SP-08)
-- =============================================================================
-- One query per question ID from analysis/questions.md. Above each query: the
-- ID, the question in words, and the approach in one line.
--
-- MEASURE DEFINITIONS USED THROUGHOUT THIS FILE (and the whole project):
--   Revenue        SUM(sales)  - the line value AFTER discount, BEFORE returns
--   Net revenue    SUM(sales) WHERE NOT is_returned
--   Profit         SUM(profit)
--   Margin %       SUM(profit) / SUM(sales)   - a ratio of sums, NEVER the
--                  average of per-row ratios (see the handbook, "ratio of
--                  sums vs sum of ratios")
--   AOV            SUM(sales) / COUNT(DISTINCT order_id)
--
-- Revenue is deliberately gross of returns so that it reconciles to the source
-- exactly. Every place where returns matter uses the explicit net measure and
-- says so. Priya's board incident was someone quietly showing gross and
-- calling it net - the fix is not to hide gross, it is to label both.
-- =============================================================================

\pset pager off


-- =============================================================================
-- SP-06 - What are total revenue, order volume, units and profit, overall and
--         per year?
-- approach: straight aggregation at line and order grain. This is the baseline
--           every other question compares against, and the row that must tie
--           to 07_reconciliation.sql.
-- =============================================================================

-- Overall
SELECT
    count(*)                                          AS order_lines,
    count(DISTINCT order_id)                          AS orders,
    count(DISTINCT customer_key)                      AS customers,
    sum(quantity)                                     AS units,
    round(sum(sales), 2)                              AS revenue,
    round(sum(profit), 2)                             AS profit,
    round(100.0 * sum(profit) / sum(sales), 2)        AS margin_pct,
    round(sum(sales) / count(DISTINCT order_id), 2)   AS aov
FROM core.fact_order_line;

-- Per year
SELECT
    d.year,
    count(*)                                             AS order_lines,
    count(DISTINCT f.order_id)                           AS orders,
    count(DISTINCT f.customer_key)                       AS customers,
    sum(f.quantity)                                      AS units,
    round(sum(f.sales), 2)                               AS revenue,
    round(sum(f.profit), 2)                              AS profit,
    round(100.0 * sum(f.profit) / sum(f.sales), 2)       AS margin_pct,
    round(sum(f.sales) / count(DISTINCT f.order_id), 2)  AS aov,
    round(100.0 * avg(f.discount), 2)                    AS avg_discount_pct
FROM core.fact_order_line f
JOIN core.dim_date d ON d.date_key = f.date_key
GROUP BY d.year
ORDER BY d.year;


-- =============================================================================
-- SP-01 - How has monthly revenue changed against the same month last year?
-- approach: aggregate to month, then LAG 12 positions over a complete monthly
--           series. LAG(12) is only safe because dim_date guarantees there is
--           no missing month - a series built from fact dates would silently
--           compare the wrong months across a gap.
-- =============================================================================

WITH monthly AS (
    SELECT d.year, d.month_no, d.year_month,
           sum(f.sales)  AS revenue,
           sum(f.profit) AS profit
    FROM core.fact_order_line f
    JOIN core.dim_date d ON d.date_key = f.date_key
    GROUP BY d.year, d.month_no, d.year_month
)
SELECT
    year_month,
    round(revenue, 2)                                                  AS revenue,
    round(lag(revenue, 12) OVER (ORDER BY year_month), 2)              AS revenue_ly,
    round(100.0 * (revenue - lag(revenue, 12) OVER (ORDER BY year_month))
                / nullif(lag(revenue, 12) OVER (ORDER BY year_month), 0), 1) AS revenue_yoy_pct,
    round(profit, 2)                                                   AS profit,
    round(100.0 * (profit - lag(profit, 12) OVER (ORDER BY year_month))
                / nullif(lag(profit, 12) OVER (ORDER BY year_month), 0), 1)  AS profit_yoy_pct,
    round(100.0 * profit / revenue, 2)                                 AS margin_pct
FROM monthly
ORDER BY year_month;


-- =============================================================================
-- SP-02 - Is growth accelerating, slowing or reversing?
-- approach: year-over-year growth by year and by quarter. Reading the SIGN of
--           the change in the growth rate, not the growth rate itself.
-- =============================================================================

WITH yearly AS (
    SELECT d.year, sum(f.sales) AS revenue, sum(f.profit) AS profit
    FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key
    GROUP BY d.year
)
SELECT
    year,
    round(revenue, 2)                                                       AS revenue,
    round(100.0 * (revenue - lag(revenue) OVER (ORDER BY year))
               / nullif(lag(revenue) OVER (ORDER BY year), 0), 1)           AS revenue_growth_pct,
    round(profit, 2)                                                        AS profit,
    round(100.0 * (profit - lag(profit) OVER (ORDER BY year))
               / nullif(lag(profit) OVER (ORDER BY year), 0), 1)            AS profit_growth_pct,
    round(100.0 * profit / revenue, 2)                                      AS margin_pct,
    round(100.0 * profit / revenue
        - lag(100.0 * profit / revenue) OVER (ORDER BY year), 2)            AS margin_change_pp
FROM yearly
ORDER BY year;


-- =============================================================================
-- SP-03 - How has profit moved against revenue, month by month?
-- approach: cumulative indexed series, both rebased to 100 at Jan-2018, so the
--           divergence is visible rather than inferred from two different axes.
-- =============================================================================

WITH monthly AS (
    SELECT d.year_month,
           sum(f.sales)  AS revenue,
           sum(f.profit) AS profit
    FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key
    GROUP BY d.year_month
),
base AS (SELECT revenue AS r0, profit AS p0 FROM monthly ORDER BY year_month LIMIT 1)
SELECT
    m.year_month,
    round(100.0 * m.revenue / b.r0, 1)          AS revenue_index,
    round(100.0 * m.profit  / b.p0, 1)          AS profit_index,
    round(100.0 * m.profit / m.revenue, 2)      AS margin_pct
FROM monthly m, base b
ORDER BY m.year_month;


-- =============================================================================
-- SP-04 - What explains the gap between revenue growth and profit growth?
-- approach: a two-factor profit bridge, per year pair. Profit change splits
--           exactly into
--             volume effect = (Rev_now - Rev_prior) * Margin_prior
--             rate effect   = (Margin_now - Margin_prior) * Rev_now
--           The two sum to the actual profit change with no residual, which is
--           why this decomposition and not a hand-waved one: it is checkable,
--           and the check is in the last column.
-- =============================================================================

WITH yearly AS (
    SELECT d.year, sum(f.sales) AS revenue, sum(f.profit) AS profit
    FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key
    GROUP BY d.year
),
paired AS (
    SELECT year,
           revenue, profit, profit / revenue                       AS margin,
           lag(revenue) OVER (ORDER BY year)                       AS revenue_prior,
           lag(profit)  OVER (ORDER BY year)                       AS profit_prior,
           lag(profit / revenue) OVER (ORDER BY year)              AS margin_prior
    FROM yearly
)
SELECT
    year,
    round(profit - profit_prior, 2)                                AS profit_change,
    round((revenue - revenue_prior) * margin_prior, 2)             AS volume_effect,
    round((margin - margin_prior) * revenue, 2)                    AS margin_rate_effect,
    round((revenue - revenue_prior) * margin_prior
        + (margin - margin_prior) * revenue
        - (profit - profit_prior), 2)                              AS residual_must_be_zero
FROM paired
WHERE profit_prior IS NOT NULL
ORDER BY year;


-- =============================================================================
-- SP-05 - Which months, products or categories contributed most to the margin
--         decline?
-- approach: contribution-to-change. For the year pair that actually declined
--           (2020 -> 2021), rank sub-categories by absolute profit change and
--           express each as a share of the total change. Contribution shares
--           can exceed 100% when some lines move the other way; that is
--           correct and worth saying out loud.
-- =============================================================================

WITH by_subcat AS (
    SELECT p.category, p.sub_category, d.year,
           sum(f.sales) AS revenue, sum(f.profit) AS profit
    FROM core.fact_order_line f
    JOIN core.dim_date d    ON d.date_key    = f.date_key
    JOIN core.dim_product p ON p.product_key = f.product_key
    WHERE d.year IN (2020, 2021)
    GROUP BY p.category, p.sub_category, d.year
),
pivoted AS (
    SELECT category, sub_category,
           sum(revenue) FILTER (WHERE year = 2020) AS revenue_2020,
           sum(revenue) FILTER (WHERE year = 2021) AS revenue_2021,
           sum(profit)  FILTER (WHERE year = 2020) AS profit_2020,
           sum(profit)  FILTER (WHERE year = 2021) AS profit_2021
    FROM by_subcat GROUP BY category, sub_category
)
SELECT
    category, sub_category,
    round(revenue_2021 - revenue_2020, 2)                                       AS revenue_change,
    round(profit_2021  - profit_2020, 2)                                        AS profit_change,
    round(100.0 * (profit_2021 - profit_2020)
          / nullif((SELECT sum(profit_2021 - profit_2020) FROM pivoted), 0), 1) AS pct_of_total_profit_change,
    round(100.0 * profit_2020 / nullif(revenue_2020, 0), 2)                     AS margin_2020_pct,
    round(100.0 * profit_2021 / nullif(revenue_2021, 0), 2)                     AS margin_2021_pct,
    round(100.0 * profit_2021 / nullif(revenue_2021, 0)
        - 100.0 * profit_2020 / nullif(revenue_2020, 0), 2)                     AS margin_change_pp
FROM pivoted
ORDER BY profit_change;

-- Same question, by month, for the year that declined.
WITH monthly AS (
    SELECT d.month_no, d.month_name,
           sum(f.profit) FILTER (WHERE d.year = 2020) AS profit_2020,
           sum(f.profit) FILTER (WHERE d.year = 2021) AS profit_2021,
           sum(f.sales)  FILTER (WHERE d.year = 2020) AS revenue_2020,
           sum(f.sales)  FILTER (WHERE d.year = 2021) AS revenue_2021
    FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key
    WHERE d.year IN (2020, 2021)
    GROUP BY d.month_no, d.month_name
)
SELECT month_no, month_name,
       round(revenue_2021 - revenue_2020, 2) AS revenue_change,
       round(profit_2021  - profit_2020, 2)  AS profit_change,
       round(100.0 * profit_2021 / revenue_2021
           - 100.0 * profit_2020 / revenue_2020, 2) AS margin_change_pp
FROM monthly
ORDER BY profit_change;


-- =============================================================================
-- SP-07 - Which calendar months run above or below a typical month?
-- approach: average each calendar month ACROSS the four years, then index
--           against the grand mean of those averages.
--           NOT a ranking of all 48 months: revenue grows every year here, so
--           ranking 48 months just rediscovers that 2021 exists. Averaging
--           across years removes the trend and leaves the shape.
-- =============================================================================

WITH month_year AS (
    SELECT d.month_no, d.month_name, d.year, sum(f.sales) AS revenue
    FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key
    GROUP BY d.month_no, d.month_name, d.year
),
month_avg AS (
    SELECT month_no, month_name, avg(revenue) AS avg_revenue
    FROM month_year GROUP BY month_no, month_name
)
SELECT
    month_no, month_name,
    round(avg_revenue, 2)                                              AS avg_month_revenue,
    round(100.0 * avg_revenue / avg(avg_revenue) OVER (), 1)           AS seasonality_index,
    round(100.0 * avg_revenue / avg(avg_revenue) OVER () - 100, 1)     AS pct_vs_typical_month
FROM month_avg
ORDER BY month_no;


-- =============================================================================
-- SP-08 - What is average order value, and how has it moved?
-- approach: collapse LINE grain to ORDER grain in a CTE first, then average.
--           avg(sales) straight off the fact table is average LINE value - a
--           different, smaller and wrong number. Median reported alongside
--           because order values are right-skewed and the mean flatters them.
-- =============================================================================

WITH orders AS (
    SELECT f.order_id, d.year,
           sum(f.sales)  AS order_value,
           sum(f.profit) AS order_profit,
           count(*)      AS lines_per_order
    FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key
    GROUP BY f.order_id, d.year
)
SELECT
    year,
    count(*)                                                           AS orders,
    round(avg(order_value), 2)                                         AS aov_mean,
    round(percentile_cont(0.5) WITHIN GROUP (ORDER BY order_value)::numeric, 2) AS aov_median,
    round(avg(lines_per_order), 2)                                     AS avg_lines_per_order,
    round(avg(order_profit), 2)                                        AS avg_order_profit,
    round(100.0 * (avg(order_value) - lag(avg(order_value)) OVER (ORDER BY year))
              / nullif(lag(avg(order_value)) OVER (ORDER BY year), 0), 1) AS aov_yoy_pct
FROM orders
GROUP BY year
ORDER BY year;

-- The wrong number, computed on purpose so the difference is on the record.
SELECT round(avg(sales), 2) AS average_LINE_value_not_aov FROM core.fact_order_line;
