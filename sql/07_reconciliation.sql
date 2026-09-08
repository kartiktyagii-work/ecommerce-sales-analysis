-- =============================================================================
-- 07_reconciliation.sql - THE GATE. Do not proceed until every row says PASS.
-- =============================================================================
--   psql -h 127.0.0.1 -U postgres -d ecommerce -v ON_ERROR_STOP=1 -f sql/07_reconciliation.sql
--
-- ONE query returning:  metric | expected | actual | difference | verdict
--
-- Not five queries you eyeball. A gate you have to squint at is a gate you
-- wave through at hour seven when you are tired.
--
-- "Expected" is always computed from the layer UPSTREAM of the one being
-- tested, so the chain is:
--     staging.orders  ->  orders_clean + rejected  ->  fact_order_line
-- Break any link and this file tells you which one.
--
-- If something does not tie, the bug is in the last two hours of work and it
-- is cheap to find. Carry it forward and every number on every dashboard page
-- is wrong - and you discover that on Day 5 with no time left.
--
-- This is the gate that would have caught the mistake in Priya's email: the
-- last analyst counted returned orders as sales and told the board the wrong
-- region was the best one. G2 below is that specific test.
--
-- Hints: HINTS.md D1.8
-- =============================================================================

\pset pager off

-- =============================================================================
-- G1. The reconciliation. One query, one row per metric, a verdict column.
--     Tolerance is exactly zero. numeric arithmetic is exact; if you had cast
--     money to float this is where you would be arguing with yourself about
--     whether 0.0000001 counts.
-- =============================================================================

WITH staged AS (
    SELECT count(*)::numeric                                       AS rows,
           sum(replace(sales,  ',', '')::numeric(14,4))            AS sales,
           sum(replace(profit, ',', '')::numeric(14,4))            AS profit,
           sum(quantity::int)::numeric                             AS quantity,
           count(DISTINCT order_id)::numeric                       AS orders,
           count(DISTINCT customer_id)::numeric                    AS customers
    FROM staging.orders
),
rejected AS (
    SELECT count(*)::numeric                                       AS rows,
           coalesce(sum(replace(sales,  ',', '')::numeric(14,4)),0) AS sales,
           coalesce(sum(replace(profit, ',', '')::numeric(14,4)),0) AS profit,
           coalesce(sum(quantity::int),0)::numeric                  AS quantity
    FROM core.rejected
),
clean AS (
    SELECT count(*)::numeric                                       AS rows,
           sum(sales)                                              AS sales,
           sum(profit)                                             AS profit,
           sum(quantity)::numeric                                  AS quantity,
           count(DISTINCT order_id)::numeric                       AS orders,
           count(DISTINCT customer_id)::numeric                    AS customers
    FROM core.orders_clean
),
fact AS (
    SELECT count(*)::numeric                                       AS rows,
           sum(sales)                                              AS sales,
           sum(profit)                                             AS profit,
           sum(quantity)::numeric                                  AS quantity,
           count(DISTINCT order_id)::numeric                       AS orders,
           count(DISTINCT customer_key)::numeric                   AS customers
    FROM core.fact_order_line
),
checks AS (
    -- Link 1: staging = clean + rejected. Nothing vanished in cleaning.
    SELECT 1 AS seq, 'staging rows = clean + rejected'      AS metric,
           s.rows AS expected, c.rows + r.rows AS actual        FROM staged s, clean c, rejected r
    UNION ALL SELECT 2, 'staging sales = clean + rejected',
           s.sales, c.sales + r.sales                           FROM staged s, clean c, rejected r
    UNION ALL SELECT 3, 'staging profit = clean + rejected',
           s.profit, c.profit + r.profit                        FROM staged s, clean c, rejected r
    UNION ALL SELECT 4, 'staging quantity = clean + rejected',
           s.quantity, c.quantity + r.quantity                  FROM staged s, clean c, rejected r

    -- Link 2: clean = fact. Nothing vanished in modelling. A dropped row here
    -- means a dimension join failed - the classic "INNER JOIN silently ate
    -- 40,000 rows because one geography key did not match" bug.
    UNION ALL SELECT 5, 'clean rows = fact rows',
           c.rows, f.rows                                       FROM clean c, fact f
    UNION ALL SELECT 6, 'clean sales = fact sales',
           c.sales, f.sales                                     FROM clean c, fact f
    UNION ALL SELECT 7, 'clean profit = fact profit',
           c.profit, f.profit                                   FROM clean c, fact f
    UNION ALL SELECT 8, 'clean quantity = fact quantity',
           c.quantity, f.quantity                               FROM clean c, fact f
    UNION ALL SELECT 9, 'clean distinct orders = fact distinct orders',
           c.orders, f.orders                                   FROM clean c, fact f
    UNION ALL SELECT 10, 'clean distinct customers = fact distinct customers',
           c.customers, f.customers                             FROM clean c, fact f

    -- Link 3: the returns file survived deduplication with its order coverage
    -- intact, and every returned order exists in the fact table.
    --
    -- Expected is deliberately NOT the raw 27,682 distinct order_ids in the
    -- returns file. Eight of those orders consisted entirely of lines that
    -- 03_cleaning quarantined (zero sales with quantity), so those orders no
    -- longer exist in the fact table and must not appear in fact_return
    -- either. Metric 15 reports that count so it stays visible rather than
    -- being buried in a tolerance.
    UNION ALL SELECT 11, 'returned orders that survived cleaning = fact_return rows',
           (SELECT count(DISTINCT r.order_id)::numeric FROM core.returns_clean r
             WHERE EXISTS (SELECT 1 FROM core.fact_order_line f WHERE f.order_id = r.order_id)),
           (SELECT count(*)::numeric FROM core.fact_return)
    UNION ALL SELECT 12, 'fact_return orders all present in fact_order_line',
           0,
           (SELECT count(*)::numeric FROM core.fact_return r
             WHERE NOT EXISTS (SELECT 1 FROM core.fact_order_line f WHERE f.order_id = r.order_id))

    -- Link 4: dimensions cover the fact completely - zero orphans.
    UNION ALL SELECT 13, 'fact rows with unresolved dimension key', 0,
           (SELECT count(*)::numeric FROM core.fact_order_line f
             WHERE NOT EXISTS (SELECT 1 FROM core.dim_date      d WHERE d.date_key      = f.date_key)
                OR NOT EXISTS (SELECT 1 FROM core.dim_customer  c WHERE c.customer_key  = f.customer_key)
                OR NOT EXISTS (SELECT 1 FROM core.dim_product   p WHERE p.product_key   = f.product_key)
                OR NOT EXISTS (SELECT 1 FROM core.dim_geography g WHERE g.geography_key = f.geography_key))

    -- Link 5: the aggregate stored on fact_return really is that order's
    -- total. If the collapse-then-join went wrong, this is where it shows.
    UNION ALL SELECT 14, 'fact_return.order_sales = sum of that order''s lines', 0,
           (SELECT count(*)::numeric FROM core.fact_return r
             JOIN (SELECT order_id, sum(sales) s FROM core.fact_order_line GROUP BY 1) l
               ON l.order_id = r.order_id
            WHERE l.s <> r.order_sales)

    -- Informational, not a pass/fail: the returned orders lost to quarantine.
    -- Recorded because it is the only place the two cleaning decisions
    -- interact, and because 8 orders is the sort of number that shows up as an
    -- unexplained rounding difference three days later.
    UNION ALL SELECT 15, 'INFO returned orders fully quarantined', 8,
           (SELECT count(DISTINCT r.order_id)::numeric FROM core.returns_clean r
             WHERE NOT EXISTS (SELECT 1 FROM core.fact_order_line f WHERE f.order_id = r.order_id))
)
SELECT metric,
       expected,
       actual,
       actual - expected                                   AS difference,
       CASE WHEN actual = expected THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM checks
ORDER BY seq;


-- =============================================================================
-- G2. Return-rate sanity check - really a fan-out detector.
--
--     Three ways of counting the same thing. The first is correct. The second
--     is what you get from a naive join and is the exact bug in Priya's email.
--     The third shows the size of the multiplication.
--
--     If "naive" is far above "correct", you multiplied returns across order
--     lines. On this data the naive figure is inflated by roughly the average
--     lines-per-order.
-- =============================================================================

WITH correct AS (
    SELECT
        (SELECT count(*)                       FROM core.fact_return)      AS returned_orders,
        (SELECT count(DISTINCT order_id)       FROM core.fact_order_line)  AS total_orders
),
naive AS (
    -- DO NOT COPY THIS PATTERN. It is here to be measured, not used.
    SELECT count(*) AS fanned_out_rows
    FROM core.fact_order_line f
    JOIN core.returns_clean  r ON r.order_id = f.order_id
)
SELECT
    c.returned_orders,
    c.total_orders,
    round(100.0 * c.returned_orders / c.total_orders, 2)                  AS return_rate_pct_correct,
    n.fanned_out_rows                                                     AS lines_of_returned_orders,
    round(100.0 * n.fanned_out_rows
          / (SELECT count(*) FROM core.fact_order_line), 2)               AS return_rate_pct_if_measured_on_lines,
    round(n.fanned_out_rows::numeric / c.returned_orders, 2)              AS inflation_factor
FROM correct c, naive n;


-- =============================================================================
-- G3. The numbers to copy into analysis/data-quality-log.md under
--     "Reconciliation record". Day 3's DAX gate checks against these.
-- =============================================================================

SELECT 'rows'              AS metric, count(*)::text              AS value FROM core.fact_order_line
UNION ALL SELECT 'sum_sales',    round(sum(sales), 4)::text       FROM core.fact_order_line
UNION ALL SELECT 'sum_profit',   round(sum(profit), 4)::text      FROM core.fact_order_line
UNION ALL SELECT 'sum_quantity', sum(quantity)::text              FROM core.fact_order_line
UNION ALL SELECT 'distinct_orders',    count(DISTINCT order_id)::text    FROM core.fact_order_line
UNION ALL SELECT 'distinct_customers', count(DISTINCT customer_key)::text FROM core.fact_order_line
UNION ALL SELECT 'returned_orders',    count(*)::text             FROM core.fact_return
UNION ALL SELECT 'overall_margin_pct',
       round(100.0 * sum(profit) / sum(sales), 2)::text           FROM core.fact_order_line;
