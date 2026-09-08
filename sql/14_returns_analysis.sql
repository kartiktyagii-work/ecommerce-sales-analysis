-- =============================================================================
-- 14_returns_analysis.sql - Returns  (register IDs RT-01..RT-05)
-- =============================================================================
-- fact_return is at ORDER grain. fact_order_line is at LINE grain.
-- Join them naively and every return multiplies by that order's line count.
-- 07_reconciliation.sql G2 measured that inflation factor at 3.23x on this
-- data - i.e. the naive join would report a return rate almost 3.25 times too
-- high, and would mis-rank every category and region while doing it.
--
-- Two safe patterns are used here:
--   * order-level questions read core.fact_return directly (already collapsed)
--   * line-level attribution reads the denormalised is_returned flag on
--     fact_order_line, which was built with EXISTS and cannot fan out
--
-- ATTRIBUTION CAVEAT, stated once and referenced everywhere after:
-- a return is recorded against a whole ORDER, not against a line. So
-- "revenue lost to returns in Chairs" means "revenue of Chairs lines that sat
-- on an order which was returned", not "Chairs that were sent back". Where the
-- source cannot distinguish them, the honest move is to say so on the visual,
-- which is what the Page 4 subtitle does.
-- =============================================================================

\pset pager off


-- =============================================================================
-- RT-01 - What is the return rate, and what revenue and profit do returned
--         orders represent?
-- approach: order grain throughout. Both the rate and the money.
-- =============================================================================

SELECT
    (SELECT count(*) FROM core.fact_return)                                   AS returned_orders,
    (SELECT count(DISTINCT order_id) FROM core.fact_order_line)               AS total_orders,
    round(100.0 * (SELECT count(*) FROM core.fact_return)
                / (SELECT count(DISTINCT order_id) FROM core.fact_order_line), 2) AS return_rate_pct,
    (SELECT sum(order_sales)  FROM core.fact_return)::numeric(14,2)           AS returned_revenue,
    (SELECT sum(order_profit) FROM core.fact_return)::numeric(14,2)           AS returned_profit,
    round(100.0 * (SELECT sum(order_sales) FROM core.fact_return)
                / (SELECT sum(sales) FROM core.fact_order_line), 2)           AS pct_of_revenue_returned;

-- Gross -> returns -> net. This is the Page 4 waterfall, and the three numbers
-- must be shown together: a "net revenue" with no gross beside it is exactly
-- the ambiguity that caused the board incident in Priya's email.
SELECT
    sum(f.sales)::numeric(14,2)                                        AS gross_revenue,
    sum(f.sales) FILTER (WHERE f.is_returned)::numeric(14,2)           AS returned_revenue,
    sum(f.sales) FILTER (WHERE NOT f.is_returned)::numeric(14,2)       AS net_revenue,
    sum(f.profit)::numeric(14,2)                                       AS gross_profit,
    sum(f.profit) FILTER (WHERE f.is_returned)::numeric(14,2)          AS returned_profit,
    sum(f.profit) FILTER (WHERE NOT f.is_returned)::numeric(14,2)      AS net_profit,
    round(100.0 * sum(f.profit) / sum(f.sales), 2)                     AS gross_margin_pct,
    round(100.0 * sum(f.profit) FILTER (WHERE NOT f.is_returned)
                / sum(f.sales)  FILTER (WHERE NOT f.is_returned), 2)   AS net_margin_pct
FROM core.fact_order_line f;


-- =============================================================================
-- RT-02 - Is the return rate rising or falling?
-- approach: returned orders / total orders per year and per month, both at
--           order grain. Two independent denominators would be a bug; both
--           come from the same order-level population.
-- =============================================================================

WITH orders_by_year AS (
    SELECT d.year, count(DISTINCT f.order_id) AS orders
    FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key
    GROUP BY d.year
),
returns_by_year AS (
    SELECT d.year, count(*) AS returned, sum(r.order_sales) AS returned_revenue
    FROM core.fact_return r JOIN core.dim_date d ON d.date_key = r.date_key
    GROUP BY d.year
)
SELECT o.year, o.orders, coalesce(rr.returned, 0) AS returned_orders,
       round(100.0 * coalesce(rr.returned, 0) / o.orders, 2)     AS return_rate_pct,
       rr.returned_revenue::numeric(14,2)                        AS returned_revenue
FROM orders_by_year o LEFT JOIN returns_by_year rr USING (year)
ORDER BY o.year;

-- Monthly, for the trend line.
WITH o AS (
    SELECT d.year_month, count(DISTINCT f.order_id) AS orders
    FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key
    GROUP BY d.year_month
),
r AS (
    SELECT d.year_month, count(*) AS returned
    FROM core.fact_return fr JOIN core.dim_date d ON d.date_key = fr.date_key
    GROUP BY d.year_month
)
SELECT o.year_month, o.orders, coalesce(r.returned, 0) AS returned,
       round(100.0 * coalesce(r.returned, 0) / o.orders, 2) AS return_rate_pct
FROM o LEFT JOIN r USING (year_month)
ORDER BY o.year_month;


-- =============================================================================
-- RT-03 - Which products, categories and regions have the highest return rates?
-- approach: line-level attribution via the is_returned flag. Every rate below
--           is sanity-checked against the 8.19% company rate in the final
--           column - a category three times the company rate would mean a
--           fan-out, not a discovery.
-- =============================================================================

SELECT
    p.category, p.sub_category,
    count(DISTINCT f.order_id)                                                  AS orders_touching,
    count(DISTINCT f.order_id) FILTER (WHERE f.is_returned)                     AS returned_orders,
    round(100.0 * count(DISTINCT f.order_id) FILTER (WHERE f.is_returned)
                / count(DISTINCT f.order_id), 2)                                AS return_rate_pct,
    sum(f.sales) FILTER (WHERE f.is_returned)::numeric(14,2)                    AS revenue_on_returned_orders,
    round(100.0 * sum(f.sales) FILTER (WHERE f.is_returned) / sum(f.sales), 2)  AS pct_revenue_returned
FROM core.fact_order_line f
JOIN core.dim_product p ON p.product_key = f.product_key
GROUP BY p.category, p.sub_category
ORDER BY return_rate_pct DESC;

SELECT
    g.region,
    count(DISTINCT f.order_id)                                              AS orders,
    count(DISTINCT f.order_id) FILTER (WHERE f.is_returned)                 AS returned_orders,
    round(100.0 * count(DISTINCT f.order_id) FILTER (WHERE f.is_returned)
                / count(DISTINCT f.order_id), 2)                            AS return_rate_pct,
    sum(f.sales) FILTER (WHERE f.is_returned)::numeric(14,2)                AS revenue_on_returned_orders
FROM core.fact_order_line f
JOIN core.dim_geography g ON g.geography_key = f.geography_key
GROUP BY g.region
ORDER BY return_rate_pct DESC;

-- Top 15 products by return rate, with a minimum order count so a product
-- ordered four times cannot top the list at 50%.
SELECT p.product_id, left(p.product_name, 45) AS product, p.sub_category,
       count(DISTINCT f.order_id)                                       AS orders,
       count(DISTINCT f.order_id) FILTER (WHERE f.is_returned)          AS returned,
       round(100.0 * count(DISTINCT f.order_id) FILTER (WHERE f.is_returned)
                   / count(DISTINCT f.order_id), 2)                     AS return_rate_pct,
       sum(f.sales)::numeric(14,2)                                      AS revenue
FROM core.fact_order_line f
JOIN core.dim_product p ON p.product_key = f.product_key
GROUP BY p.product_id, p.product_name, p.sub_category
HAVING count(DISTINCT f.order_id) >= 200
ORDER BY return_rate_pct DESC
LIMIT 15;


-- =============================================================================
-- RT-04 - How much profit is lost annually to returns?
-- approach: order-grain profit on returned orders, per year.
--
--           WHAT THIS NUMBER IS NOT: it is not "profit destroyed". The data
--           records that an order was returned; it does not record whether the
--           goods were resold, what the handling cost was, or whether a
--           refund was partial. So this is the profit BOOKED on orders that
--           were subsequently returned - an upper bound on the exposure and a
--           reasonable planning figure, and it must be labelled that way.
--           Saying which of those you mean is the difference between a
--           finding and a number someone else has to defend for you.
-- =============================================================================

SELECT d.year,
       count(*)                                    AS returned_orders,
       sum(r.order_sales)::numeric(14,2)           AS revenue_on_returned_orders,
       sum(r.order_profit)::numeric(14,2)          AS profit_on_returned_orders,
       round(100.0 * sum(r.order_profit) / sum(r.order_sales), 2) AS margin_on_returned_pct
FROM core.fact_return r JOIN core.dim_date d ON d.date_key = r.date_key
GROUP BY d.year ORDER BY d.year;

-- Are returned orders systematically different from kept ones? If returned
-- orders are bigger, or more discounted, that is a mechanism rather than an
-- observation - and mechanisms are what Priya asked for.
SELECT
    CASE WHEN f.is_returned THEN 'returned' ELSE 'kept' END      AS bucket,
    count(DISTINCT f.order_id)                                   AS orders,
    round(sum(f.sales) / count(DISTINCT f.order_id), 2)          AS aov,
    round(100.0 * avg(f.discount), 2)                            AS avg_discount_pct,
    round(100.0 * sum(f.profit) / sum(f.sales), 2)               AS margin_pct,
    round(avg(f.quantity), 2)                                    AS avg_units_per_line
FROM core.fact_order_line f
GROUP BY 1;


-- =============================================================================
-- RT-05 - Are the highest-return sub-categories also the top sellers?
-- approach: rank by return rate and by revenue, then compare the two ranks.
--           A high return rate on a small line is a nuisance; the same rate on
--           a top-three seller is a strategy problem, and only the overlap
--           tells you which one you have.
-- =============================================================================

WITH sc AS (
    SELECT p.category, p.sub_category,
           sum(f.sales)                                           AS revenue,
           count(DISTINCT f.order_id)                             AS orders,
           count(DISTINCT f.order_id) FILTER (WHERE f.is_returned) AS returned,
           sum(f.sales) FILTER (WHERE f.is_returned)              AS returned_revenue,
           sum(f.profit)                                          AS profit,
           sum(f.profit) FILTER (WHERE NOT f.is_returned)         AS net_profit
    FROM core.fact_order_line f
    JOIN core.dim_product p ON p.product_key = f.product_key
    GROUP BY p.category, p.sub_category
)
SELECT
    category, sub_category,
    rank() OVER (ORDER BY revenue DESC)                            AS revenue_rank,
    rank() OVER (ORDER BY 1.0 * returned / orders DESC)            AS return_rate_rank,
    revenue::numeric(14,2)                                         AS revenue,
    round(100.0 * returned / orders, 2)                            AS return_rate_pct,
    returned_revenue::numeric(14,2)                                AS revenue_on_returned_orders,
    net_profit::numeric(14,2)                                      AS net_profit_after_returns,
    round(100.0 * net_profit / (revenue - returned_revenue), 2)    AS net_margin_pct,
    CASE WHEN rank() OVER (ORDER BY revenue DESC) <= 6
          AND rank() OVER (ORDER BY 1.0 * returned / orders DESC) <= 6
         THEN 'TOP SELLER + HIGH RETURNS' ELSE '' END              AS flag
FROM sc
ORDER BY revenue_rank;
