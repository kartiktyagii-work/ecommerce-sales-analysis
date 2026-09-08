-- =============================================================================
-- 11_product_performance.sql - Product performance, and the margin question
--                              (register IDs PP-01..PP-08, DP-01..DP-04)
-- =============================================================================
-- This file holds the most valuable query in the project: the one that becomes
-- a decision. Finance believes discounting is destroying margin on some lines.
-- Prove or disprove it, and put a number on it.
--
-- Margin is ALWAYS SUM(profit) / SUM(sales) - a ratio of sums. Never
-- AVG(profit / sales). A $2 line at -50% and a $20,000 line at +30% average to
-- -10% if you take the mean of the ratios, and to +29.9% if you do it right.
-- The first number is a lie about a rounding error.
-- =============================================================================

\pset pager off


-- =============================================================================
-- PP-01 - Which products and categories generate the most revenue?
-- approach: aggregate and rank at both levels. Share-of-total included because
--           a rank without a share tells you the order but not the stakes.
-- =============================================================================

SELECT
    p.category,
    count(DISTINCT p.product_key)                              AS products,
    sum(f.sales)::numeric(14,2)                                AS revenue,
    round(100.0 * sum(f.sales) / sum(sum(f.sales)) OVER (), 1) AS pct_of_revenue,
    sum(f.profit)::numeric(14,2)                               AS profit,
    round(100.0 * sum(f.profit) / sum(sum(f.profit)) OVER (), 1) AS pct_of_profit,
    round(100.0 * sum(f.profit) / sum(f.sales), 2)             AS margin_pct
FROM core.fact_order_line f
JOIN core.dim_product p ON p.product_key = f.product_key
GROUP BY p.category
ORDER BY revenue DESC;

SELECT
    p.category, p.sub_category,
    sum(f.sales)::numeric(14,2)                                AS revenue,
    round(100.0 * sum(f.sales) / sum(sum(f.sales)) OVER (), 1) AS pct_of_revenue,
    sum(f.profit)::numeric(14,2)                               AS profit,
    round(100.0 * sum(f.profit) / sum(f.sales), 2)             AS margin_pct,
    round(100.0 * avg(f.discount), 2)                          AS avg_discount_pct
FROM core.fact_order_line f
JOIN core.dim_product p ON p.product_key = f.product_key
GROUP BY p.category, p.sub_category
ORDER BY revenue DESC;

-- Top 15 products by revenue.
SELECT
    p.product_id, left(p.product_name, 50) AS product, p.sub_category,
    sum(f.sales)::numeric(14,2)                    AS revenue,
    sum(f.profit)::numeric(14,2)                   AS profit,
    round(100.0 * sum(f.profit) / sum(f.sales), 2) AS margin_pct
FROM core.fact_order_line f
JOIN core.dim_product p ON p.product_key = f.product_key
GROUP BY p.product_id, p.product_name, p.sub_category
ORDER BY revenue DESC
LIMIT 15;


-- =============================================================================
-- PP-03 - Which products or sub-categories are losing money?
-- approach: negative contribution profit, ranked by how much. A minimum line
--           count keeps a single freak order out of the recommendation.
-- =============================================================================

SELECT
    p.product_id, left(p.product_name, 45) AS product, p.sub_category,
    count(*)                                       AS lines,
    sum(f.sales)::numeric(14,2)                    AS revenue,
    sum(f.profit)::numeric(14,2)                   AS profit,
    round(100.0 * sum(f.profit) / sum(f.sales), 2) AS margin_pct,
    round(100.0 * avg(f.discount), 1)              AS avg_discount_pct
FROM core.fact_order_line f
JOIN core.dim_product p ON p.product_key = f.product_key
GROUP BY p.product_id, p.product_name, p.sub_category
HAVING sum(f.profit) < 0 AND count(*) >= 50
ORDER BY profit
LIMIT 20;

-- How much of the catalogue loses money at all, and what does it cost?
SELECT
    count(*) FILTER (WHERE profit < 0)                     AS loss_making_products,
    count(*)                                               AS total_products,
    round(100.0 * count(*) FILTER (WHERE profit < 0) / count(*), 1) AS pct_loss_making,
    sum(profit) FILTER (WHERE profit < 0)::numeric(14,2)   AS total_loss,
    sum(revenue) FILTER (WHERE profit < 0)::numeric(14,2)  AS revenue_at_a_loss
FROM (
    SELECT f.product_key, sum(f.sales) AS revenue, sum(f.profit) AS profit
    FROM core.fact_order_line f GROUP BY f.product_key
) x;


-- =============================================================================
-- PP-04 - Is Furniture actually dragging profitability, as Sales believes?
-- approach: test the stakeholder's stated hypothesis directly - Furniture vs
--           the rest on level, trend and contribution to the decline. A
--           hypothesis deserves a yes/no with a number, not a table to squint
--           at.
-- =============================================================================

WITH by_cat_year AS (
    SELECT p.category, d.year, sum(f.sales) AS revenue, sum(f.profit) AS profit
    FROM core.fact_order_line f
    JOIN core.dim_product p ON p.product_key = f.product_key
    JOIN core.dim_date    d ON d.date_key    = f.date_key
    GROUP BY p.category, d.year
)
SELECT
    category,
    sum(revenue) FILTER (WHERE year = 2018)::numeric(14,2) AS revenue_2018,
    sum(revenue) FILTER (WHERE year = 2021)::numeric(14,2) AS revenue_2021,
    round(100.0 * sum(profit) FILTER (WHERE year = 2018)
              / sum(revenue) FILTER (WHERE year = 2018), 2) AS margin_2018_pct,
    round(100.0 * sum(profit) FILTER (WHERE year = 2021)
              / sum(revenue) FILTER (WHERE year = 2021), 2) AS margin_2021_pct,
    round(100.0 * sum(profit) FILTER (WHERE year = 2021) / sum(revenue) FILTER (WHERE year = 2021)
        - 100.0 * sum(profit) FILTER (WHERE year = 2018) / sum(revenue) FILTER (WHERE year = 2018), 2)
                                                           AS margin_change_pp,
    (sum(profit) FILTER (WHERE year = 2021)
   - sum(profit) FILTER (WHERE year = 2020))::numeric(14,2) AS profit_change_2020_21
FROM by_cat_year
GROUP BY category
ORDER BY margin_2021_pct;

-- The counter-test: if Furniture were removed entirely, what would the
-- company's margin trajectory look like? If the slide persists without it,
-- Furniture is a symptom and not the cause.
WITH y AS (
    SELECT d.year,
           sum(f.sales)                                             AS revenue_all,
           sum(f.profit)                                            AS profit_all,
           sum(f.sales)  FILTER (WHERE p.category <> 'Furniture')   AS revenue_ex_furn,
           sum(f.profit) FILTER (WHERE p.category <> 'Furniture')   AS profit_ex_furn
    FROM core.fact_order_line f
    JOIN core.dim_product p ON p.product_key = f.product_key
    JOIN core.dim_date    d ON d.date_key    = f.date_key
    GROUP BY d.year
)
SELECT year,
       round(100.0 * profit_all / revenue_all, 2)         AS margin_all_pct,
       round(100.0 * profit_ex_furn / revenue_ex_furn, 2) AS margin_excl_furniture_pct
FROM y ORDER BY year;


-- =============================================================================
-- PP-05 - Which categories deteriorated most in margin year over year?
-- approach: percentage-point change, not percent change. Margin moving from
--           4% to 2% is "-2 pp" and "-50%"; the first is the honest one.
-- =============================================================================

WITH m AS (
    SELECT p.category, p.sub_category, d.year,
           sum(f.profit) / sum(f.sales) AS margin
    FROM core.fact_order_line f
    JOIN core.dim_product p ON p.product_key = f.product_key
    JOIN core.dim_date    d ON d.date_key    = f.date_key
    GROUP BY p.category, p.sub_category, d.year
)
SELECT category, sub_category,
       round(100.0 * max(margin) FILTER (WHERE year = 2018), 2) AS margin_2018_pct,
       round(100.0 * max(margin) FILTER (WHERE year = 2019), 2) AS margin_2019_pct,
       round(100.0 * max(margin) FILTER (WHERE year = 2020), 2) AS margin_2020_pct,
       round(100.0 * max(margin) FILTER (WHERE year = 2021), 2) AS margin_2021_pct,
       round(100.0 * (max(margin) FILTER (WHERE year = 2021)
                    - max(margin) FILTER (WHERE year = 2018)), 2) AS change_2018_21_pp
FROM m
GROUP BY category, sub_category
ORDER BY change_2018_21_pp;


-- =============================================================================
-- PP-06 - Which products combine high sales with weak margins?
-- approach: quadrants defined from the DATA - the median revenue and the
--           median margin across products - not from a threshold I invented.
--           "Why 20%?" is an unanswerable question in a review; "it is the
--           median" is not.
-- =============================================================================

WITH prod AS (
    SELECT f.product_key,
           sum(f.sales)  AS revenue,
           sum(f.profit) AS profit,
           sum(f.profit) / sum(f.sales) AS margin,
           avg(f.discount) AS avg_discount
    FROM core.fact_order_line f
    GROUP BY f.product_key
    HAVING count(*) >= 50           -- exclude long-tail noise from the cuts
),
cuts AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY revenue) AS median_revenue,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY margin)  AS median_margin
    FROM prod
)
SELECT
    CASE WHEN pr.revenue >= c.median_revenue AND pr.margin >= c.median_margin THEN '1 high rev / high margin'
         WHEN pr.revenue >= c.median_revenue AND pr.margin <  c.median_margin THEN '2 HIGH REV / LOW MARGIN'
         WHEN pr.revenue <  c.median_revenue AND pr.margin >= c.median_margin THEN '3 low rev / high margin'
         ELSE                                                                      '4 low rev / low margin'
    END                                              AS quadrant,
    count(*)                                         AS products,
    sum(pr.revenue)::numeric(14,2)                   AS revenue,
    sum(pr.profit)::numeric(14,2)                    AS profit,
    round(100.0 * sum(pr.profit) / sum(pr.revenue), 2) AS margin_pct,
    round(100.0 * avg(pr.avg_discount), 1)           AS avg_discount_pct
FROM prod pr, cuts c
GROUP BY 1 ORDER BY 1;

-- The names in the problem quadrant, worst first. This is an action list.
WITH prod AS (
    SELECT f.product_key, sum(f.sales) AS revenue, sum(f.profit) AS profit,
           sum(f.profit) / sum(f.sales) AS margin, avg(f.discount) AS avg_discount
    FROM core.fact_order_line f GROUP BY f.product_key HAVING count(*) >= 50
),
cuts AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY revenue) AS median_revenue,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY margin)  AS median_margin
    FROM prod
)
SELECT p.product_id, left(p.product_name, 45) AS product, p.sub_category,
       pr.revenue::numeric(14,2)              AS revenue,
       pr.profit::numeric(14,2)               AS profit,
       round(100.0 * pr.margin, 2)            AS margin_pct,
       round(100.0 * pr.avg_discount, 1)      AS avg_discount_pct
FROM prod pr
CROSS JOIN cuts c
JOIN core.dim_product p ON p.product_key = pr.product_key
WHERE pr.revenue >= c.median_revenue AND pr.margin < c.median_margin
ORDER BY pr.margin
LIMIT 20;


-- =============================================================================
-- PP-07 - Which sub-categories are below threshold in a MAJORITY of months?
-- approach: count the months, do not average them. An average hides a line
--           that is fine for ten months and catastrophic for two - and those
--           two problems need completely different fixes.
--           Threshold stated explicitly: the company-wide margin in that same
--           month, so it moves with the business instead of being a fixed
--           number that ages badly.
-- =============================================================================

WITH company_month AS (
    SELECT d.year_month, sum(f.profit) / sum(f.sales) AS company_margin
    FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key
    GROUP BY d.year_month
),
subcat_month AS (
    SELECT p.category, p.sub_category, d.year_month,
           sum(f.profit) / sum(f.sales) AS margin
    FROM core.fact_order_line f
    JOIN core.dim_product p ON p.product_key = f.product_key
    JOIN core.dim_date    d ON d.date_key    = f.date_key
    GROUP BY p.category, p.sub_category, d.year_month
)
SELECT
    s.category, s.sub_category,
    count(*)                                                       AS months_observed,
    count(*) FILTER (WHERE s.margin < c.company_margin)            AS months_below_company,
    round(100.0 * count(*) FILTER (WHERE s.margin < c.company_margin) / count(*), 0)
                                                                   AS pct_months_below,
    count(*) FILTER (WHERE s.margin < 0)                           AS months_negative,
    round(100.0 * avg(s.margin), 2)                                AS avg_monthly_margin_pct,
    CASE WHEN count(*) FILTER (WHERE s.margin < c.company_margin) >= 0.75 * count(*)
         THEN 'CHRONIC' ELSE '' END                                AS verdict
FROM subcat_month s
JOIN company_month c USING (year_month)
GROUP BY s.category, s.sub_category
ORDER BY months_below_company DESC, months_negative DESC;


-- =============================================================================
-- PP-08 - What share of products generates 80% of revenue?
-- approach: rank by revenue, cumulative sum over the ranked list, find where
--           the running share crosses 80%.
-- =============================================================================

WITH prod AS (
    SELECT f.product_key, sum(f.sales) AS revenue
    FROM core.fact_order_line f GROUP BY f.product_key
),
ranked AS (
    SELECT product_key, revenue,
           row_number() OVER (ORDER BY revenue DESC)                       AS rn,
           sum(revenue) OVER (ORDER BY revenue DESC
                              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_revenue,
           sum(revenue) OVER ()                                            AS total_revenue,
           count(*)     OVER ()                                            AS total_products
    FROM prod
)
SELECT
    min(rn)                                                        AS products_to_reach_80pct,
    max(total_products)                                            AS total_products,
    round(100.0 * min(rn) / max(total_products), 1)                AS pct_of_catalogue
FROM ranked
WHERE cum_revenue >= 0.80 * total_revenue;

-- The full curve, thinned to every 50th product, for the Pareto visual.
WITH prod AS (
    SELECT f.product_key, sum(f.sales) AS revenue
    FROM core.fact_order_line f GROUP BY f.product_key
),
ranked AS (
    SELECT row_number() OVER (ORDER BY revenue DESC) AS rn,
           sum(revenue) OVER (ORDER BY revenue DESC
                              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_revenue,
           sum(revenue) OVER () AS total_revenue
    FROM prod
)
SELECT rn AS product_rank,
       round(100.0 * cum_revenue / total_revenue, 1) AS cumulative_pct_of_revenue
FROM ranked WHERE rn % 100 = 0 OR rn = 1 ORDER BY rn;


-- =============================================================================
-- DP-01 - How much discounting is happening, and has it risen?
-- approach: three different views of "how much", because they answer different
--           questions - the average rate, the money given away, and the share
--           of revenue sold at a deep discount.
--
--           NOTE ON AVERAGING A RATE: avg(discount) is the average LINE's
--           discount, which weights a $3 pencil the same as a $3,000 copier.
--           The weighted rate (discount dollars / gross list value) is the one
--           Finance means. Both are here, and they differ - which is itself
--           worth showing.
-- =============================================================================

SELECT
    d.year,
    round(100.0 * avg(f.discount), 2)                                AS avg_discount_pct_unweighted,
    round(100.0 * sum(f.discount_value) / sum(f.gross_list_value), 2) AS avg_discount_pct_weighted,
    sum(f.discount_value)::numeric(14,2)                             AS discount_dollars,
    round(100.0 * count(*) FILTER (WHERE f.discount = 0) / count(*), 1)    AS pct_lines_no_discount,
    round(100.0 * count(*) FILTER (WHERE f.discount >= 0.50) / count(*), 1) AS pct_lines_50pct_plus,
    round(100.0 * sum(f.sales) FILTER (WHERE f.discount >= 0.50) / sum(f.sales), 1)
                                                                     AS pct_revenue_50pct_plus
FROM core.fact_order_line f
JOIN core.dim_date d ON d.date_key = f.date_key
GROUP BY d.year ORDER BY d.year;


-- =============================================================================
-- DP-02 - Which discount bands are associated with low or negative margins?
-- approach: 10-point bands, margin per band. A minimum band size is enforced
--           so a band of 40 lines cannot flip the conclusion on noise.
-- =============================================================================

WITH banded AS (
    SELECT
        CASE WHEN f.discount = 0 THEN '00%'
             ELSE lpad((floor(f.discount * 10) * 10)::int::text, 2, '0') || '-'
                  || ((floor(f.discount * 10) * 10)::int + 9)::text || '%' END AS discount_band,
        f.sales, f.profit, f.quantity
    FROM core.fact_order_line f
)
SELECT
    discount_band,
    count(*)                                            AS lines,
    round(100.0 * count(*) / sum(count(*)) OVER (), 1)  AS pct_of_lines,
    sum(sales)::numeric(14,2)                           AS revenue,
    sum(profit)::numeric(14,2)                          AS profit,
    round(100.0 * sum(profit) / sum(sales), 2)          AS margin_pct
FROM banded
GROUP BY discount_band
HAVING count(*) >= 1000
ORDER BY discount_band;


-- =============================================================================
-- DP-03 - Are 50%+ discounted orders losing money, and what does it cost?
-- approach: answer Finance's question literally, then annualise it. Ritu asked
--           "is that true and how much is it costing us annually" - so the
--           output is a yes/no and a per-year figure, not a table.
-- =============================================================================

SELECT
    count(*)                                                AS lines,
    count(DISTINCT f.order_id)                              AS orders_affected,
    sum(f.sales)::numeric(14,2)                             AS revenue,
    sum(f.profit)::numeric(14,2)                            AS profit,
    round(100.0 * sum(f.profit) / sum(f.sales), 2)          AS margin_pct,
    round(sum(f.profit) / 4, 2)                             AS profit_per_year_avg,
    sum(f.discount_value)::numeric(14,2)                    AS discount_given_away
FROM core.fact_order_line f
WHERE f.discount >= 0.50;

-- Split by year, because "annually" is not the same as "one quarter of four years"
-- when the behaviour is growing this fast.
SELECT d.year,
       count(*)                                       AS lines,
       sum(f.sales)::numeric(14,2)                    AS revenue,
       sum(f.profit)::numeric(14,2)                   AS profit,
       round(100.0 * sum(f.profit) / sum(f.sales), 2) AS margin_pct
FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key
WHERE f.discount >= 0.50
GROUP BY d.year ORDER BY d.year;

-- And the same for every band above 20%, so the cost is attributable to a level
-- rather than to one arbitrary cut-off.
SELECT
    CASE WHEN f.discount >= 0.50 THEN 'e 50%+'
         WHEN f.discount >= 0.40 THEN 'd 40-49%'
         WHEN f.discount >= 0.30 THEN 'c 30-39%'
         WHEN f.discount >= 0.20 THEN 'b 20-29%'
         ELSE                         'a under 20%' END      AS band,
    count(*)                                                 AS lines,
    sum(f.sales)::numeric(14,2)                              AS revenue,
    sum(f.profit)::numeric(14,2)                             AS profit,
    round(100.0 * sum(f.profit) / sum(f.sales), 2)           AS margin_pct
FROM core.fact_order_line f
GROUP BY 1 ORDER BY 1;


-- =============================================================================
-- DP-04 - At what discount does margin turn negative, by sub-category?
--         *** The headline query of the project. ***
-- approach: margin per 5-point discount band per sub-category, then LAG over
--           the bands to find where the sign flips. The band where margin
--           first goes negative, per sub-category, is the number you set
--           policy at.
--
--           Minimum band size of 200 lines: without it, a band containing four
--           lines can "prove" a threshold, and that is how a policy gets set
--           on noise.
-- =============================================================================

WITH banded AS (
    SELECT p.sub_category,
           (round(f.discount * 20) / 20)::numeric(4,2) AS discount_band,   -- 5-point buckets
           f.sales, f.profit
    FROM core.fact_order_line f
    JOIN core.dim_product p ON p.product_key = f.product_key
),
band_margin AS (
    SELECT sub_category, discount_band,
           count(*)                     AS lines,
           sum(sales)                   AS revenue,
           sum(profit)                  AS profit,
           sum(profit) / sum(sales)     AS margin
    FROM banded
    GROUP BY sub_category, discount_band
    HAVING count(*) >= 200
),
flagged AS (
    SELECT *,
           lag(margin)        OVER (PARTITION BY sub_category ORDER BY discount_band) AS prev_margin,
           lag(discount_band) OVER (PARTITION BY sub_category ORDER BY discount_band) AS prev_band
    FROM band_margin
)
SELECT
    sub_category,
    prev_band                                       AS last_profitable_discount,
    discount_band                                   AS first_lossmaking_discount,
    round(100.0 * prev_margin, 2)                   AS margin_at_last_profitable_pct,
    round(100.0 * margin, 2)                        AS margin_at_first_lossmaking_pct,
    lines                                           AS lines_in_lossmaking_band
FROM flagged
WHERE margin < 0 AND prev_margin >= 0
ORDER BY discount_band, sub_category;

-- The full grid behind that answer - this is what the Page 1 heatmap shows.
WITH banded AS (
    SELECT p.sub_category,
           (round(f.discount * 20) / 20)::numeric(4,2) AS discount_band,
           f.sales, f.profit
    FROM core.fact_order_line f
    JOIN core.dim_product p ON p.product_key = f.product_key
)
SELECT sub_category, discount_band,
       count(*)                                   AS lines,
       sum(sales)::numeric(14,2)                  AS revenue,
       round(100.0 * sum(profit) / sum(sales), 2) AS margin_pct
FROM banded
GROUP BY sub_category, discount_band
HAVING count(*) >= 200
ORDER BY sub_category, discount_band;

-- Sub-categories that never recover: negative margin at EVERY band above the
-- threshold, not just one. Distinguishes a real break-even point from noise.
WITH banded AS (
    SELECT p.sub_category, (round(f.discount * 20) / 20)::numeric(4,2) AS discount_band,
           f.sales, f.profit
    FROM core.fact_order_line f JOIN core.dim_product p ON p.product_key = f.product_key
),
bm AS (
    SELECT sub_category, discount_band, sum(profit)/sum(sales) AS margin, count(*) AS lines
    FROM banded GROUP BY 1,2 HAVING count(*) >= 200
)
SELECT sub_category,
       min(discount_band) FILTER (WHERE margin < 0)  AS first_negative_band,
       max(discount_band) FILTER (WHERE margin >= 0) AS highest_profitable_band,
       count(*) FILTER (WHERE margin < 0)            AS negative_bands,
       count(*)                                      AS bands_observed
FROM bm
GROUP BY sub_category
HAVING count(*) FILTER (WHERE margin < 0) > 0
ORDER BY first_negative_band, sub_category;
