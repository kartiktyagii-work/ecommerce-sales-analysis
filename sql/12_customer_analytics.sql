-- =============================================================================
-- 12_customer_analytics.sql - Customer analytics  (register IDs CA-01..CA-05)
-- =============================================================================
-- THE AS-OF DATE IS FIXED AT 2021-12-31, the last day in the data. Never
-- current_date. Anything computed from current_date changes tomorrow, so the
-- recency scores in this file would silently stop matching the numbers written
-- into the register - and you would find out in an interview, not before.
--
-- The cohort query is the most expensive thing in the sprint and the change
-- request on Day 3 demotes this whole page. It is kept because it is already
-- written and because it answers a question Priya will ask again in March.
-- =============================================================================

\pset pager off

\set as_of '2021-12-31'


-- =============================================================================
-- CA-05 - How many unique and active customers, and what does the order
--         frequency distribution look like?
-- approach: distinct counts overall and per year, then the shape of orders per
--           customer. The mean order frequency is nearly useless on its own
--           here because the distribution is heavily skewed - the histogram is
--           the answer, the mean is the headline.
-- =============================================================================

SELECT
    count(DISTINCT customer_key)                                        AS customers_ever,
    count(DISTINCT order_id)                                            AS orders,
    round(count(DISTINCT order_id)::numeric / count(DISTINCT customer_key), 2)
                                                                        AS avg_orders_per_customer,
    round(sum(sales) / count(DISTINCT customer_key), 2)                 AS revenue_per_customer
FROM core.fact_order_line;

SELECT d.year,
       count(DISTINCT f.customer_key)                                   AS active_customers,
       count(DISTINCT f.order_id)                                       AS orders,
       round(count(DISTINCT f.order_id)::numeric
             / count(DISTINCT f.customer_key), 2)                       AS orders_per_active_customer,
       round(sum(f.sales) / count(DISTINCT f.customer_key), 2)          AS revenue_per_active_customer
FROM core.fact_order_line f JOIN core.dim_date d ON d.date_key = f.date_key
GROUP BY d.year ORDER BY d.year;

-- Distribution of orders per customer over the whole window.
WITH per_customer AS (
    SELECT customer_key, count(DISTINCT order_id) AS orders
    FROM core.fact_order_line GROUP BY customer_key
)
SELECT
    CASE WHEN orders = 1 THEN '1 order'
         WHEN orders = 2 THEN '2 orders'
         WHEN orders BETWEEN 3 AND 5   THEN '3-5 orders'
         WHEN orders BETWEEN 6 AND 10  THEN '6-10 orders'
         ELSE '11+ orders' END                                          AS frequency_band,
    count(*)                                                            AS customers,
    round(100.0 * count(*) / sum(count(*)) OVER (), 1)                  AS pct_of_customers,
    sum(orders)                                                         AS orders
FROM per_customer
GROUP BY 1
ORDER BY min(orders);


-- =============================================================================
-- CA-03a - What proportion of customers repeat-purchase?
-- approach: a repeat customer has >= 2 DISTINCT ORDERS. Not two lines - an
--           order with three lines is one purchase decision, not three.
--           This distinction changes the answer by more than 60 points.
-- =============================================================================

WITH per_customer AS (
    SELECT customer_key,
           count(DISTINCT order_id) AS orders,
           count(*)                 AS lines,
           sum(sales)               AS revenue
    FROM core.fact_order_line GROUP BY customer_key
)
SELECT
    count(*)                                                          AS customers,
    count(*) FILTER (WHERE orders >= 2)                               AS repeat_customers,
    round(100.0 * count(*) FILTER (WHERE orders >= 2) / count(*), 1)  AS repeat_rate_pct,
    round(100.0 * sum(revenue) FILTER (WHERE orders >= 2) / sum(revenue), 1)
                                                                      AS pct_revenue_from_repeat,
    -- The wrong version, on the record: counting LINES instead of ORDERS.
    round(100.0 * count(*) FILTER (WHERE lines >= 2) / count(*), 1)   AS wrong_repeat_rate_on_lines
FROM per_customer;


-- =============================================================================
-- CA-01 - Who are our highest-value customers?
-- approach: revenue, profit and order count per customer, ranked. Masked name
--           shown alongside the real one because Legal asked for masking on
--           Day 3 - see the change request.
-- =============================================================================

SELECT
    c.customer_id,
    c.customer_name_masked,
    c.segment,
    count(DISTINCT f.order_id)                     AS orders,
    sum(f.sales)::numeric(14,2)                    AS revenue,
    sum(f.profit)::numeric(14,2)                   AS profit,
    round(100.0 * sum(f.profit) / sum(f.sales), 1) AS margin_pct,
    max(f.date_key)                                AS last_order
FROM core.fact_order_line f
JOIN core.dim_customer c ON c.customer_key = f.customer_key
GROUP BY c.customer_id, c.customer_name_masked, c.segment
ORDER BY revenue DESC
LIMIT 20;


-- =============================================================================
-- CA-02 - How concentrated is revenue among the largest customers?
-- approach: rank customers by revenue, take the cumulative share at the 10th,
--           20th and 50th percentile of the customer base.
-- =============================================================================

WITH per_customer AS (
    SELECT customer_key, sum(sales) AS revenue, sum(profit) AS profit
    FROM core.fact_order_line GROUP BY customer_key
),
ranked AS (
    SELECT revenue, profit,
           row_number() OVER (ORDER BY revenue DESC)              AS rn,
           count(*)     OVER ()                                   AS n,
           sum(revenue) OVER (ORDER BY revenue DESC
                              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_revenue,
           sum(revenue) OVER ()                                   AS total_revenue
    FROM per_customer
)
SELECT
    '  top 1%'  AS bucket, round(100.0 * max(cum_revenue) FILTER (WHERE rn <= 0.01 * n) / max(total_revenue), 1) AS pct_of_revenue FROM ranked
UNION ALL SELECT ' top 10%', round(100.0 * max(cum_revenue) FILTER (WHERE rn <= 0.10 * n) / max(total_revenue), 1) FROM ranked
UNION ALL SELECT ' top 20%', round(100.0 * max(cum_revenue) FILTER (WHERE rn <= 0.20 * n) / max(total_revenue), 1) FROM ranked
UNION ALL SELECT ' top 50%', round(100.0 * max(cum_revenue) FILTER (WHERE rn <= 0.50 * n) / max(total_revenue), 1) FROM ranked;


-- =============================================================================
-- CA-04 - RFM segmentation, and who is worth winning back.
-- approach: NTILE(5) on each of recency, frequency and monetary.
--           RECENCY INVERTS - bought yesterday must score 5, not 1 - so it is
--           ordered by days-since ASCENDING while the other two are DESC.
--           Getting that backwards produces a segmentation that recommends
--           you chase your best customers and ignore your churned ones, and
--           it looks completely plausible until someone reads a name on it.
-- =============================================================================

CREATE OR REPLACE VIEW core.v_customer_rfm AS
WITH base AS (
    SELECT
        f.customer_key,
        DATE '2021-12-31' - max(f.date_key)  AS recency_days,
        count(DISTINCT f.order_id)           AS frequency,
        sum(f.sales)                         AS monetary,
        sum(f.profit)                        AS profit,
        min(f.date_key)                      AS first_order,
        max(f.date_key)                      AS last_order
    FROM core.fact_order_line f
    GROUP BY f.customer_key
),
scored AS (
    SELECT *,
           ntile(5) OVER (ORDER BY recency_days ASC)  AS r_score,   -- inverted, on purpose
           ntile(5) OVER (ORDER BY frequency DESC)    AS f_score,
           ntile(5) OVER (ORDER BY monetary DESC)     AS m_score
    FROM base
)
SELECT *,
       (6 - r_score) AS r_rank_display,   -- 5 = most recent, for reading
       CASE
           WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN 'Champions'
           WHEN r_score <= 2 AND m_score <= 2                  THEN 'Loyal high value'
           WHEN r_score <= 2                                   THEN 'Recent, low value'
           WHEN r_score >= 4 AND m_score <= 2                  THEN 'AT RISK - high value'
           WHEN r_score >= 4 AND f_score >= 4                  THEN 'Lost / one-off'
           ELSE                                                     'Middle'
       END AS rfm_segment
FROM scored;

SELECT rfm_segment,
       count(*)                                          AS customers,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct_of_customers,
       sum(monetary)::numeric(14,2)                      AS revenue,
       round(100.0 * sum(monetary) / sum(sum(monetary)) OVER (), 1) AS pct_of_revenue,
       round(avg(recency_days))                          AS avg_days_since_last_order,
       round(avg(frequency), 2)                          AS avg_orders
FROM core.v_customer_rfm
GROUP BY rfm_segment
ORDER BY revenue DESC;

-- The win-back list: high historical value, gone quiet. This is an action
-- list with names on it, which is what "decision" means for CA-04.
SELECT c.customer_id, c.customer_name_masked, c.segment,
       r.frequency                    AS orders,
       r.monetary::numeric(14,2)      AS lifetime_revenue,
       r.profit::numeric(14,2)        AS lifetime_profit,
       r.recency_days                 AS days_since_last_order,
       r.last_order
FROM core.v_customer_rfm r
JOIN core.dim_customer c ON c.customer_key = r.customer_key
WHERE r.rfm_segment = 'AT RISK - high value'
ORDER BY r.monetary DESC
LIMIT 20;

-- How much money is sitting in the at-risk segment in total? The size of the
-- prize, which is what makes it a decision rather than a list.
SELECT
    count(*)                                            AS at_risk_customers,
    sum(monetary)::numeric(14,2)                        AS lifetime_revenue_at_risk,
    sum(profit)::numeric(14,2)                          AS lifetime_profit_at_risk,
    round(avg(recency_days))                            AS avg_days_quiet
FROM core.v_customer_rfm
WHERE rfm_segment = 'AT RISK - high value';


-- =============================================================================
-- CA-03b - Cohort retention.
-- approach: cohort = the month of a customer's FIRST order. Then, for each
--           cohort, the share still active n months later.
--           CORRECTNESS CHECK: months_since = 0 must be 100.0 for every
--           cohort. If it is not, the cohort assignment is wrong and nothing
--           else in the matrix means anything.
--           Timeboxed to 45 minutes per the sprint plan; it came in under.
-- =============================================================================

WITH first_order AS (
    SELECT customer_key, date_trunc('month', min(date_key))::date AS cohort_month
    FROM core.fact_order_line GROUP BY customer_key
),
activity AS (
    SELECT DISTINCT f.customer_key, date_trunc('month', f.date_key)::date AS active_month
    FROM core.fact_order_line f
),
joined AS (
    SELECT fo.cohort_month,
           (EXTRACT(YEAR FROM a.active_month) - EXTRACT(YEAR FROM fo.cohort_month)) * 12
         + (EXTRACT(MONTH FROM a.active_month) - EXTRACT(MONTH FROM fo.cohort_month)) AS months_since,
           a.customer_key
    FROM activity a JOIN first_order fo USING (customer_key)
),
sizes AS (
    SELECT cohort_month, count(*) AS cohort_size FROM first_order GROUP BY cohort_month
)
SELECT
    to_char(j.cohort_month, 'YYYY-MM')                            AS cohort,
    s.cohort_size,
    round(100.0 * count(*) FILTER (WHERE months_since = 0)  / s.cohort_size, 1) AS m0_must_be_100,
    round(100.0 * count(*) FILTER (WHERE months_since = 1)  / s.cohort_size, 1) AS m1,
    round(100.0 * count(*) FILTER (WHERE months_since = 3)  / s.cohort_size, 1) AS m3,
    round(100.0 * count(*) FILTER (WHERE months_since = 6)  / s.cohort_size, 1) AS m6,
    round(100.0 * count(*) FILTER (WHERE months_since = 12) / s.cohort_size, 1) AS m12
FROM joined j JOIN sizes s USING (cohort_month)
GROUP BY j.cohort_month, s.cohort_size
ORDER BY j.cohort_month;

-- Cohort quality over time, condensed: are the customers we acquired later
-- worth less than the ones we acquired early? Grouped by acquisition YEAR so
-- the answer fits on one screen and in one sentence.
WITH first_order AS (
    SELECT customer_key,
           min(date_key)                                   AS first_date,
           EXTRACT(YEAR FROM min(date_key))::int           AS cohort_year
    FROM core.fact_order_line GROUP BY customer_key
),
lifetime AS (
    SELECT f.customer_key, count(DISTINCT f.order_id) AS orders,
           sum(f.sales) AS revenue, sum(f.profit) AS profit
    FROM core.fact_order_line f GROUP BY f.customer_key
)
SELECT
    fo.cohort_year,
    count(*)                                                       AS customers_acquired,
    round(avg(l.orders), 2)                                        AS avg_lifetime_orders,
    round(avg(l.revenue), 2)                                       AS avg_lifetime_revenue,
    round(100.0 * count(*) FILTER (WHERE l.orders >= 2) / count(*), 1) AS pct_who_reordered,
    -- Normalised for the shorter observation window: orders per month of
    -- exposure. Without this, later cohorts always look worse simply because
    -- they have had less time - the single most common cohort-analysis error.
    round(avg(l.orders / GREATEST(1,
        (DATE '2021-12-31' - fo.first_date) / 30.44)), 3)          AS orders_per_month_exposed
FROM first_order fo JOIN lifetime l USING (customer_key)
GROUP BY fo.cohort_year
ORDER BY fo.cohort_year;


-- =============================================================================
-- CA-03c - ADDED ON DAY 5, AFTER OPENING _sealed/_DATASET-KEY.md.
--          This query is the miss, written up honestly rather than quietly
--          back-dated.
--
-- The key says a weak cohort was planted: customers acquired between
-- 2020-04-01 and 2020-09-30 repeat at 55% of normal. My Day 2 analysis grouped
-- cohorts by acquisition YEAR, which averages a six-month effect across twelve
-- months and dilutes it below the threshold at which anyone would look twice.
-- I saw that later cohorts were worse and attributed all of it to a shorter
-- observation window - a reasonable explanation that happened to be wrong.
--
-- The lesson generalises past this dataset: if the effect you are hunting is
-- shorter than the bucket you are grouping by, you cannot see it, and the
-- result will still look plausible. Group at the finest grain the data
-- supports, THEN aggregate up - not the other way round.
-- =============================================================================

WITH first_order AS (
    SELECT customer_key, min(date_key) AS first_date
    FROM core.fact_order_line GROUP BY customer_key
),
lifetime AS (
    SELECT customer_key, count(DISTINCT order_id) AS orders, sum(sales) AS revenue
    FROM core.fact_order_line GROUP BY customer_key
)
SELECT
    CASE
        WHEN fo.first_date BETWEEN DATE '2020-04-01' AND DATE '2020-09-30' THEN 'Apr-Sep 2020  <- the weak cohort'
        WHEN fo.first_date BETWEEN DATE '2019-10-01' AND DATE '2020-03-31' THEN 'Oct 2019-Mar 2020 (before)'
        WHEN fo.first_date BETWEEN DATE '2020-10-01' AND DATE '2021-03-31' THEN 'Oct 2020-Mar 2021 (after)'
    END                                                                AS acquisition_window,
    count(*)                                                           AS customers,
    round(avg(l.orders), 3)                                            AS avg_lifetime_orders,
    round(100.0 * count(*) FILTER (WHERE l.orders >= 2) / count(*), 1) AS pct_who_reordered,
    round(avg(l.revenue), 2)                                           AS avg_lifetime_revenue
FROM first_order fo JOIN lifetime l USING (customer_key)
WHERE fo.first_date BETWEEN DATE '2019-10-01' AND DATE '2021-03-31'
GROUP BY 1
ORDER BY 1;

-- Result: 54.8% of the Apr-Sep 2020 cohort reordered, against 77.0% for the
-- six months before it and 59.7% for the six months after. Six months of
-- acquisition, roughly 15,500 customers, worth materially less than the
-- cohorts either side of them.
