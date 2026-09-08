-- =============================================================================
-- 18_gate_values.sql - the reference numbers the DAX measures are checked against
-- =============================================================================
--   psql -h 127.0.0.1 -U postgres -d ecommerce -f sql/18_gate_values.sql
--
-- One query, one row per measure, so the Day 3 gate is a side-by-side read
-- rather than a hunt through six analysis files. Results and the mismatches
-- this caught: powerbi/dax-vs-sql-gate.md.
--
-- Re-run this after ANY change to 03_cleaning.sql or 05_dimensional_model.sql.
-- If the build changes and these numbers are not regenerated, the gate is
-- checking DAX against history.
-- =============================================================================

\pset pager off

-- Tier 1 - unfiltered totals.
SELECT 'Revenue'                AS measure, round(sum(sales), 2)::text  AS sql_value FROM core.fact_order_line
UNION ALL SELECT 'Profit',            round(sum(profit), 2)::text       FROM core.fact_order_line
UNION ALL SELECT 'Units',             sum(quantity)::text               FROM core.fact_order_line
UNION ALL SELECT 'Order Lines',       count(*)::text                    FROM core.fact_order_line
UNION ALL SELECT 'Orders',            count(DISTINCT order_id)::text    FROM core.fact_order_line
UNION ALL SELECT 'Customers',         count(DISTINCT customer_key)::text FROM core.fact_order_line
UNION ALL SELECT 'Discount Value',    round(sum(discount_value), 2)::text     FROM core.fact_order_line
UNION ALL SELECT 'Gross List Value',  round(sum(gross_list_value), 2)::text   FROM core.fact_order_line
UNION ALL SELECT 'Margin %',          round(100.0 * sum(profit) / sum(sales), 2)::text FROM core.fact_order_line
UNION ALL SELECT 'AOV',               round(sum(sales) / count(DISTINCT order_id), 2)::text FROM core.fact_order_line
UNION ALL SELECT 'Discount % (weighted)',
       round(100.0 * sum(discount_value) / sum(gross_list_value), 2)::text FROM core.fact_order_line

-- Tier 2 - one dimension at a time.
UNION ALL SELECT 'Revenue | 2021',    round(sum(f.sales), 2)::text
       FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key WHERE d.year = 2021
UNION ALL SELECT 'Profit | 2021',     round(sum(f.profit), 2)::text
       FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key WHERE d.year = 2021
UNION ALL SELECT 'Revenue | West',    round(sum(f.sales), 2)::text
       FROM core.fact_order_line f JOIN core.dim_geography g ON g.geography_key = f.geography_key
       WHERE g.region = 'West'
UNION ALL SELECT 'Revenue | Technology 2021', round(sum(f.sales), 2)::text
       FROM core.fact_order_line f
       JOIN core.dim_product p ON p.product_key = f.product_key
       JOIN core.dim_date    d ON d.date_key    = f.date_key
       WHERE p.category = 'Technology' AND d.year = 2021
UNION ALL SELECT 'Margin % | Tables 2021', round(100.0 * sum(f.profit) / sum(f.sales), 2)::text
       FROM core.fact_order_line f
       JOIN core.dim_product p ON p.product_key = f.product_key
       JOIN core.dim_date    d ON d.date_key    = f.date_key
       WHERE p.sub_category = 'Tables' AND d.year = 2021
UNION ALL SELECT 'Profit at 50%+ discount | 2021', round(sum(f.profit), 2)::text
       FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key
       WHERE f.discount >= 0.50 AND d.year = 2021
UNION ALL SELECT 'Revenue Target | 2021', round(sum(revenue_target), 2)::text
       FROM core.fact_target WHERE year = 2021

-- Tier 3 - the four that break most easily.
UNION ALL SELECT 'Returned Orders',   count(*)::text FROM core.fact_return
UNION ALL SELECT 'Return Rate %',
       round(100.0 * (SELECT count(*) FROM core.fact_return)
                   / (SELECT count(DISTINCT order_id) FROM core.fact_order_line), 2)::text
UNION ALL SELECT 'Returned Revenue',  round(sum(sales), 2)::text  FROM core.fact_order_line WHERE is_returned
UNION ALL SELECT 'Net Revenue',       round(sum(sales), 2)::text  FROM core.fact_order_line WHERE NOT is_returned
UNION ALL SELECT 'Net Profit',        round(sum(profit), 2)::text FROM core.fact_order_line WHERE NOT is_returned
UNION ALL SELECT 'Repeat Customers',  count(*)::text
       FROM (SELECT customer_key FROM core.fact_order_line GROUP BY 1 HAVING count(DISTINCT order_id) >= 2) x
UNION ALL SELECT 'Repeat Rate %',
       round(100.0 * (SELECT count(*) FROM (SELECT customer_key FROM core.fact_order_line
              GROUP BY 1 HAVING count(DISTINCT order_id) >= 2) a)
                   / (SELECT count(DISTINCT customer_key) FROM core.fact_order_line), 1)::text

-- The wrong versions, computed on purpose. If a DAX measure matches one of
-- THESE instead, you know exactly which mistake you made.
UNION ALL SELECT 'WRONG AOV (average line value)',  round(avg(sales), 2)::text FROM core.fact_order_line
UNION ALL SELECT 'WRONG return rate (line grain)',
       round(100.0 * count(*) FILTER (WHERE is_returned) / count(*), 2)::text FROM core.fact_order_line
UNION ALL SELECT 'WRONG repeat rate (lines not orders)',
       round(100.0 * (SELECT count(*) FROM (SELECT customer_key FROM core.fact_order_line
              GROUP BY 1 HAVING count(*) >= 2) a)
                   / (SELECT count(DISTINCT customer_key) FROM core.fact_order_line), 1)::text
ORDER BY 1;


-- Tier 4 - decomposition checks. Each must be exactly 0.
SELECT 'regions sum to total revenue' AS check_name,
       (SELECT sum(sales) FROM core.fact_order_line)
     - (SELECT sum(r) FROM (SELECT sum(f.sales) r FROM core.fact_order_line f
          JOIN core.dim_geography g ON g.geography_key = f.geography_key GROUP BY g.region) x) AS difference
UNION ALL
SELECT 'categories sum to total revenue',
       (SELECT sum(sales) FROM core.fact_order_line)
     - (SELECT sum(r) FROM (SELECT sum(f.sales) r FROM core.fact_order_line f
          JOIN core.dim_product p ON p.product_key = f.product_key GROUP BY p.category) x)
UNION ALL
SELECT 'net + returned = gross revenue',
       (SELECT sum(sales) FROM core.fact_order_line)
     - (SELECT sum(sales) FILTER (WHERE NOT is_returned) + sum(sales) FILTER (WHERE is_returned)
          FROM core.fact_order_line);
