-- =============================================================================
-- 16_discount_counterfactual.sql - The counterfactual
-- =============================================================================
-- Written on DAY 3, after the change request. Not before.
--
-- "What would we have earned with discounts capped at X%?"
--
-- ---------------------------------------------------------------------------
-- THE ARITHMETIC, stated once so every number below is checkable
-- ---------------------------------------------------------------------------
-- For a line: sales = list x (1 - d)   and   profit = sales - cost.
-- The build stored gross_list_value = sales / (1 - d), so `list` is known.
-- Cost is whatever the source implies: cost = sales - profit.
--
-- Capping the discount at c on a line where d > c:
--     new_sales  = list x (1 - c)
--     new_profit = new_sales - cost = new_profit_old + (new_sales - sales)
--
-- The cost term cancels, so the profit gain per line is exactly the revenue
-- gain. That is only true because COST DOES NOT MOVE WITH THE DISCOUNT, which
-- is the one physical assumption in the whole model and is a safe one: a
-- discount changes what the customer pays, not what the goods cost.
--
-- ---------------------------------------------------------------------------
-- THE ASSUMPTION THAT MATTERS, and why the answer is a range
-- ---------------------------------------------------------------------------
-- The naive number assumes every one of those orders still happens at the
-- lower discount. That is certainly false - some of them converted BECAUSE of
-- the discount. Price elasticity is not observable in this data: there is no
-- record of an order that did not happen.
--
-- So it is bounded rather than guessed:
--
--   UPPER  every affected order survives the cap, repriced. Full recovery.
--   LOWER  every order containing a line above the cap is lost ENTIRELY -
--          taking its other, profitable lines with it. This is the strict
--          bound, and it is the one people forget: killing a 60%-off line
--          also kills the three full-price lines sitting next to it on the
--          same order.
--   MIDDLE a stated retention rate between the two. The recommendation names
--          the rate it assumes instead of hiding it.
--
-- A range with a stated assumption is a senior answer. A point estimate here
-- is a guess in a suit.
--
-- Hints: HINTS.md D3.1
-- =============================================================================

\pset pager off


-- =============================================================================
-- !1 - Size of the exposure. How much business sits above each candidate cap?
-- approach: before modelling anything, show what is in scope. A cap that
--           touches 0.3% of revenue is not a board decision.
-- =============================================================================

WITH caps AS (SELECT unnest(ARRAY[0.50, 0.40, 0.30, 0.25, 0.20, 0.15]) AS cap)
SELECT
    c.cap,
    count(*) FILTER (WHERE f.discount > c.cap)                                  AS lines_above_cap,
    count(DISTINCT f.order_id) FILTER (WHERE f.discount > c.cap)                AS orders_touched,
    round(100.0 * count(DISTINCT f.order_id) FILTER (WHERE f.discount > c.cap)
                / count(DISTINCT f.order_id), 1)                                AS pct_of_orders,
    sum(f.sales) FILTER (WHERE f.discount > c.cap)::numeric(14,2)               AS revenue_above_cap,
    round(100.0 * sum(f.sales) FILTER (WHERE f.discount > c.cap) / sum(f.sales), 1)
                                                                                AS pct_of_revenue,
    sum(f.profit) FILTER (WHERE f.discount > c.cap)::numeric(14,2)              AS profit_above_cap
FROM core.fact_order_line f
CROSS JOIN caps c
GROUP BY c.cap
ORDER BY c.cap DESC;


-- =============================================================================
-- !2 - THE COUNTERFACTUAL. Upper and lower bound per candidate cap, 2021.
-- approach: 2021 only, because Priya asked "what would we have earned LAST
--           year". Doing it on all four years would flatter the answer -
--           the behaviour is growing fast, so the four-year average is well
--           below the current run rate.
-- =============================================================================

WITH caps AS (SELECT unnest(ARRAY[0.50, 0.40, 0.30, 0.25, 0.20, 0.15]) AS cap),
lines_2021 AS (
    SELECT f.order_id, f.discount, f.sales, f.profit, f.gross_list_value
    FROM core.fact_order_line f
    JOIN core.dim_date d ON d.date_key = f.date_key
    WHERE d.year = 2021
),
-- Upper bound: reprice every line above the cap; keep everything else.
upper_bound AS (
    SELECT c.cap,
           sum(CASE WHEN l.discount > c.cap
                    THEN l.gross_list_value * (1 - c.cap) - l.sales
                    ELSE 0 END)                                       AS profit_recovered
    FROM lines_2021 l CROSS JOIN caps c
    GROUP BY c.cap
),
-- Lower bound: any ORDER containing a line above the cap disappears whole.
affected_orders AS (
    SELECT c.cap, l.order_id
    FROM lines_2021 l CROSS JOIN caps c
    WHERE l.discount > c.cap
    GROUP BY c.cap, l.order_id
),
lower_bound AS (
    SELECT a.cap,
           count(DISTINCT a.order_id)                                 AS orders_lost,
           sum(l.profit)                                              AS profit_forgone,
           sum(l.sales)                                               AS revenue_forgone
    FROM affected_orders a
    JOIN lines_2021 l ON l.order_id = a.order_id
    GROUP BY a.cap
),
base AS (SELECT sum(profit) AS profit_2021, sum(sales) AS revenue_2021 FROM lines_2021)
SELECT
    u.cap,
    b.profit_2021::numeric(14,2)                                      AS actual_profit_2021,
    u.profit_recovered::numeric(14,2)                                 AS upper_bound_gain,
    round(100.0 * u.profit_recovered / b.profit_2021, 1)              AS upper_bound_gain_pct,
    (-lb.profit_forgone)::numeric(14,2)                               AS lower_bound_gain,
    round(100.0 * (-lb.profit_forgone) / b.profit_2021, 1)            AS lower_bound_gain_pct,
    lb.orders_lost,
    lb.revenue_forgone::numeric(14,2)                                 AS revenue_at_risk_if_all_lost
FROM upper_bound u
JOIN lower_bound lb USING (cap)
CROSS JOIN base b
ORDER BY u.cap DESC;


-- =============================================================================
-- !2b - Sensitivity to the assumption itself.
-- approach: instead of arguing about whether orders survive, show the answer
--           as a function of the survival rate. Whoever disagrees with the
--           recommendation can find their own assumption on this table and
--           read off the consequence - which ends the argument faster than
--           defending a single number.
--
--           Modelled for a 30% cap, which is where DP-02 showed the company
--           blended margin crosses zero.
-- =============================================================================

WITH lines_2021 AS (
    SELECT f.order_id, f.discount, f.sales, f.profit, f.gross_list_value
    FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key
    WHERE d.year = 2021
),
cap AS (SELECT 0.30::numeric AS c),
affected AS (
    SELECT DISTINCT l.order_id FROM lines_2021 l, cap WHERE l.discount > cap.c
),
repriced AS (
    SELECT sum(CASE WHEN l.discount > cap.c
                    THEN l.gross_list_value * (1 - cap.c) - l.sales ELSE 0 END) AS gain_if_kept,
           sum(l.profit) FILTER (WHERE l.order_id IN (SELECT order_id FROM affected))
                                                                                AS profit_of_affected_orders
    FROM lines_2021 l, cap
),
survival AS (SELECT unnest(ARRAY[1.00, 0.90, 0.75, 0.50, 0.25, 0.00]) AS survival_rate)
SELECT
    s.survival_rate,
    -- Orders that survive are repriced (gain); orders that are lost take their
    -- whole contribution with them.
    (r.gain_if_kept * s.survival_rate
     - r.profit_of_affected_orders * (1 - s.survival_rate))::numeric(14,2)  AS net_profit_change_2021,
    round(100.0 * (r.gain_if_kept * s.survival_rate
     - r.profit_of_affected_orders * (1 - s.survival_rate))
     / (SELECT sum(profit) FROM lines_2021), 1)                             AS pct_of_2021_profit
FROM repriced r CROSS JOIN survival s
ORDER BY s.survival_rate DESC;

-- The break-even survival rate: below this, the cap destroys more than it
-- recovers. This single number is the honest headline of the whole analysis.
WITH lines_2021 AS (
    SELECT f.order_id, f.discount, f.sales, f.profit, f.gross_list_value
    FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key
    WHERE d.year = 2021
),
cap AS (SELECT 0.30::numeric AS c),
affected AS (SELECT DISTINCT l.order_id FROM lines_2021 l, cap WHERE l.discount > cap.c),
r AS (
    SELECT sum(CASE WHEN l.discount > cap.c
                    THEN l.gross_list_value * (1 - cap.c) - l.sales ELSE 0 END) AS gain_if_kept,
           sum(l.profit) FILTER (WHERE l.order_id IN (SELECT order_id FROM affected))
                                                                                AS profit_of_affected
    FROM lines_2021 l, cap
)
SELECT
    gain_if_kept::numeric(14,2)                                   AS gain_if_all_survive,
    profit_of_affected::numeric(14,2)                             AS profit_at_stake,
    round(100.0 * profit_of_affected / (gain_if_kept + profit_of_affected), 1)
                                                                  AS breakeven_survival_rate_pct
FROM r;


-- =============================================================================
-- !3 - THE BETTER POLICY: a cap per sub-category, at its own break-even.
-- approach: one company-wide cap is blunt - DP-04 showed break-even ranges
--           from 15% (Tables) to 65% (Binders). A per-sub-category cap set at
--           each line's own break-even recovers more margin while touching
--           far less business, because it leaves the categories that can
--           genuinely afford a deep discount alone.
--
--           This is the recommendation that goes in the write-up.
-- =============================================================================

-- The thresholds, recomputed here so this file stands alone.
CREATE OR REPLACE VIEW core.v_subcat_breakeven AS
WITH banded AS (
    SELECT p.sub_category,
           (round(f.discount * 20) / 20)::numeric(4,2) AS discount_band,
           f.sales, f.profit
    FROM core.fact_order_line f
    JOIN core.dim_product p ON p.product_key = f.product_key
),
bm AS (
    SELECT sub_category, discount_band, sum(profit) / sum(sales) AS margin, count(*) AS lines
    FROM banded GROUP BY 1, 2 HAVING count(*) >= 200
)
SELECT sub_category,
       coalesce(max(discount_band) FILTER (WHERE margin >= 0), 0.85) AS breakeven_cap
FROM bm GROUP BY sub_category;

SELECT * FROM core.v_subcat_breakeven ORDER BY breakeven_cap, sub_category;

-- What the per-sub-category cap is worth in 2021, on the same two bounds.
WITH l AS (
    SELECT f.order_id, f.discount, f.sales, f.profit, f.gross_list_value,
           b.breakeven_cap AS cap
    FROM core.fact_order_line f
    JOIN core.dim_date    d ON d.date_key    = f.date_key
    JOIN core.dim_product p ON p.product_key = f.product_key
    JOIN core.v_subcat_breakeven b ON b.sub_category = p.sub_category
    WHERE d.year = 2021
),
affected AS (SELECT DISTINCT order_id FROM l WHERE discount > cap)
SELECT
    'per sub-category cap at its own break-even'                         AS policy,
    count(*) FILTER (WHERE discount > cap)                               AS lines_repriced,
    (SELECT count(*) FROM affected)                                      AS orders_touched,
    round(100.0 * (SELECT count(*) FROM affected)
                / count(DISTINCT order_id), 1)                           AS pct_of_orders,
    sum(CASE WHEN discount > cap
             THEN gross_list_value * (1 - cap) - sales ELSE 0 END)::numeric(14,2)
                                                                         AS upper_bound_gain,
    (-sum(profit) FILTER (WHERE order_id IN (SELECT order_id FROM affected)))::numeric(14,2)
                                                                         AS lower_bound_gain
FROM l;

-- Side by side with the flat 30% cap, so the trade is explicit.
WITH l AS (
    SELECT f.order_id, f.discount, f.sales, f.profit, f.gross_list_value
    FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key
    WHERE d.year = 2021
),
flat AS (
    SELECT 'flat 30% cap' AS policy,
           count(*) FILTER (WHERE discount > 0.30)                       AS lines_repriced,
           count(DISTINCT order_id) FILTER (WHERE discount > 0.30)       AS orders_touched,
           sum(CASE WHEN discount > 0.30
                    THEN gross_list_value * 0.70 - sales ELSE 0 END)     AS upper_gain
    FROM l
),
per_sc AS (
    SELECT 'per sub-category cap' AS policy,
           count(*) FILTER (WHERE x.discount > x.cap)                    AS lines_repriced,
           count(DISTINCT x.order_id) FILTER (WHERE x.discount > x.cap)  AS orders_touched,
           sum(CASE WHEN x.discount > x.cap
                    THEN x.gross_list_value * (1 - x.cap) - x.sales ELSE 0 END) AS upper_gain
    FROM (
        SELECT f.order_id, f.discount, f.sales, f.gross_list_value, b.breakeven_cap AS cap
        FROM core.fact_order_line f
        JOIN core.dim_date    d ON d.date_key    = f.date_key
        JOIN core.dim_product p ON p.product_key = f.product_key
        JOIN core.v_subcat_breakeven b ON b.sub_category = p.sub_category
        WHERE d.year = 2021
    ) x
)
SELECT policy, lines_repriced, orders_touched, upper_gain::numeric(14,2) AS upper_bound_gain
FROM (SELECT * FROM flat UNION ALL SELECT * FROM per_sc) z
ORDER BY upper_gain DESC;


-- =============================================================================
-- !4 - What the cap does NOT fix.
-- approach: the honest counterweight. SP-04's decomposition showed that only
--           part of the margin decline is discount-driven; the rest happened
--           on business sold at FULL price. A discount cap cannot touch that,
--           and saying so before someone else does is what makes the rest of
--           the analysis credible.
-- =============================================================================

WITH b AS (
    SELECT d.year,
           CASE WHEN f.discount = 0 THEN 'sold at full price'
                ELSE 'sold at a discount' END AS bucket,
           sum(f.sales) AS revenue, sum(f.profit) AS profit
    FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key
    WHERE d.year IN (2018, 2021)
    GROUP BY 1, 2
)
SELECT bucket,
       round(100.0 * max(profit) FILTER (WHERE year = 2018)
                   / max(revenue) FILTER (WHERE year = 2018), 2) AS margin_2018_pct,
       round(100.0 * max(profit) FILTER (WHERE year = 2021)
                   / max(revenue) FILTER (WHERE year = 2021), 2) AS margin_2021_pct,
       round(100.0 * max(profit) FILTER (WHERE year = 2021) / max(revenue) FILTER (WHERE year = 2021)
           - 100.0 * max(profit) FILTER (WHERE year = 2018) / max(revenue) FILTER (WHERE year = 2018), 2)
                                                                 AS change_pp,
       max(revenue) FILTER (WHERE year = 2021)::numeric(14,2)    AS revenue_2021
FROM b GROUP BY bucket ORDER BY bucket;

-- And where that full-price erosion actually lives.
SELECT g.region,
       round(100.0 * sum(f.profit) FILTER (WHERE d.year = 2018)
                   / sum(f.sales)  FILTER (WHERE d.year = 2018), 2) AS full_price_margin_2018_pct,
       round(100.0 * sum(f.profit) FILTER (WHERE d.year = 2021)
                   / sum(f.sales)  FILTER (WHERE d.year = 2021), 2) AS full_price_margin_2021_pct,
       round(100.0 * sum(f.profit) FILTER (WHERE d.year = 2021) / sum(f.sales) FILTER (WHERE d.year = 2021)
           - 100.0 * sum(f.profit) FILTER (WHERE d.year = 2018) / sum(f.sales) FILTER (WHERE d.year = 2018), 2)
                                                                    AS change_pp
FROM core.fact_order_line f
JOIN core.dim_geography g ON g.geography_key = f.geography_key
JOIN core.dim_date      d ON d.date_key      = f.date_key
WHERE f.discount = 0 AND d.year IN (2018, 2021)
GROUP BY g.region
ORDER BY change_pp;
