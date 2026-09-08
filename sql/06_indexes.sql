-- =============================================================================
-- 06_indexes.sql - make it fast, and prove you made it fast
-- =============================================================================
--   psql -h 127.0.0.1 -U postgres -d ecommerce -v ON_ERROR_STOP=1 -f sql/06_indexes.sql
--
-- At ~1M rows a missing index stops being theoretical. This block exists so
-- you feel that, fix it, and can talk about it afterwards.
--
-- The exercise, in order:
--   1. Pick your slowest analytical query so far.
--   2. EXPLAIN (ANALYZE, BUFFERS) it. Record the time and the plan nodes.
--   3. Look for Seq Scan on fact_order_line inside a query that filters or
--      joins on a small subset of it.
--   4. Add the index the plan is asking for. ANALYZE the table.
--   5. Re-run the EXPLAIN. Record the new time.
--   6. Write BOTH numbers into analysis/query-tuning.md.
--
-- Do not index everything. Each index costs write time and space. The point is
-- to show you can identify WHICH one a plan is asking for.
--
-- The honest headline finding of this block, recorded in query-tuning.md:
-- indexes did NOT help the big aggregations. A query that touches 60% of a
-- 1M-row table is *supposed* to sequential-scan; forcing an index there makes
-- it slower. Indexes paid off on the SELECTIVE queries - one category, one
-- region, one customer, one month - which is exactly what a dashboard slicer
-- generates. That distinction is the thing worth being able to say out loud.
--
-- Hints: HINTS.md D1.7
-- =============================================================================

\timing on
\pset pager off

-- =============================================================================
-- I1. BASELINE. The query is the one a dashboard actually issues when a user
--     clicks a category on Page 2: monthly revenue and margin for one
--     sub-category in one region. It is selective - roughly 0.4% of the fact
--     table - which is precisely the shape an index can help.
-- =============================================================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT d.year, d.month_no,
       sum(f.sales)  AS revenue,
       sum(f.profit) AS profit
FROM core.fact_order_line f
JOIN core.dim_date      d ON d.date_key      = f.date_key
JOIN core.dim_product   p ON p.product_key   = f.product_key
JOIN core.dim_geography g ON g.geography_key = f.geography_key
WHERE p.sub_category = 'Tables'
  AND g.region       = 'West'
GROUP BY d.year, d.month_no
ORDER BY d.year, d.month_no;

-- Second baseline: the whole-table aggregation behind the Page 1 KPI row.
-- Recorded so the "an index would not help this one" claim is evidenced, not
-- asserted.
EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(sales) AS revenue, sum(profit) AS profit, count(DISTINCT order_id) AS orders
FROM core.fact_order_line;


-- =============================================================================
-- I2. Indexes.
--
--     Why these five and nothing else:
--       date_key       every visual is filtered by the date slicer
--       product_key    Page 2 lives here; also the sub-category joins
--       geography_key  Page 3 map and region slicer
--       customer_key   Page 4 top-customer table and RFM
--       order_id       AOV, order counts and the returns link all group by it
--     Not indexed: sales / profit / quantity. Nothing filters on a measure -
--     they are aggregated, and an index on a column you only SUM is dead
--     weight that slows every insert.
-- =============================================================================

CREATE INDEX IF NOT EXISTS ix_fol_date      ON core.fact_order_line (date_key);
CREATE INDEX IF NOT EXISTS ix_fol_product   ON core.fact_order_line (product_key);
CREATE INDEX IF NOT EXISTS ix_fol_geography ON core.fact_order_line (geography_key);
CREATE INDEX IF NOT EXISTS ix_fol_customer  ON core.fact_order_line (customer_key);
CREATE INDEX IF NOT EXISTS ix_fol_order     ON core.fact_order_line (order_id);

-- Covering index for the single most-run shape in the project: aggregate
-- measures for a slice of dates. INCLUDE puts the measures in the index leaf
-- so the plan can answer from the index alone (index-only scan) without going
-- back to the heap for every row.
CREATE INDEX IF NOT EXISTS ix_fol_date_covering
    ON core.fact_order_line (date_key) INCLUDE (sales, profit, quantity);

-- Partial index for the discount work, which is the headline analysis after
-- the change request. 5% of the table matches, so the index is small and the
-- planner will actually choose it.
CREATE INDEX IF NOT EXISTS ix_fol_high_discount
    ON core.fact_order_line (discount, product_key)
    WHERE discount >= 0.50;

CREATE INDEX IF NOT EXISTS ix_fr_date ON core.fact_return (date_key);

-- Dimension lookups the plans above depend on.
CREATE INDEX IF NOT EXISTS ix_dim_product_subcat ON core.dim_product  (sub_category);
CREATE INDEX IF NOT EXISTS ix_dim_geo_region     ON core.dim_geography (region);

ANALYZE core.fact_order_line;
ANALYZE core.fact_return;
ANALYZE core.dim_product;
ANALYZE core.dim_geography;


-- =============================================================================
-- I3. AFTER. The same two EXPLAINs. Record the delta in query-tuning.md.
-- =============================================================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT d.year, d.month_no,
       sum(f.sales)  AS revenue,
       sum(f.profit) AS profit
FROM core.fact_order_line f
JOIN core.dim_date      d ON d.date_key      = f.date_key
JOIN core.dim_product   p ON p.product_key   = f.product_key
JOIN core.dim_geography g ON g.geography_key = f.geography_key
WHERE p.sub_category = 'Tables'
  AND g.region       = 'West'
GROUP BY d.year, d.month_no
ORDER BY d.year, d.month_no;

EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(sales) AS revenue, sum(profit) AS profit, count(DISTINCT order_id) AS orders
FROM core.fact_order_line;

-- The discount query the partial index was built for.
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.sub_category, count(*) AS lines, sum(f.sales) AS revenue, sum(f.profit) AS profit
FROM core.fact_order_line f
JOIN core.dim_product p ON p.product_key = f.product_key
WHERE f.discount >= 0.50
GROUP BY p.sub_category
ORDER BY profit;


-- =============================================================================
-- I4. What the indexes cost. Half of the answer to "should I add an index?"
--     is what it costs you, and most people only ever quote the benefit.
-- =============================================================================

SELECT
    indexrelname                                   AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid))   AS size,
    idx_scan                                       AS times_used
FROM pg_stat_user_indexes
WHERE relname IN ('fact_order_line', 'fact_return')
ORDER BY pg_relation_size(indexrelid) DESC;

SELECT
    pg_size_pretty(pg_table_size('core.fact_order_line'))   AS heap_size,
    pg_size_pretty(pg_indexes_size('core.fact_order_line')) AS index_size,
    pg_size_pretty(pg_total_relation_size('core.fact_order_line')) AS total;

\timing off
