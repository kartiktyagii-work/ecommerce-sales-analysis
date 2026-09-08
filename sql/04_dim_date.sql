-- =============================================================================
-- 04_dim_date.sql - the calendar
-- =============================================================================
--   psql -h 127.0.0.1 -U postgres -d ecommerce -v ON_ERROR_STOP=1 -f sql/04_dim_date.sql
--
-- Build from generate_series, NEVER from the dates present in the fact table.
-- A date table built from facts has a hole on every day with no orders, and
-- Power BI time intelligence then mis-computes across the gaps, silently.
--
-- Window: 2018-01-01 to 2021-12-31 -> 1,461 rows (four years, one leap day).
--
-- Include a NUMERIC month column alongside the month name. Power BI needs it
-- to sort Jan/Feb/Mar correctly instead of alphabetically (Apr, Aug, Dec...).
-- This catches everyone exactly once.
--
-- date_key is the DATE itself, not an integer like 20180101. At this size the
-- storage difference is irrelevant and a real date column means Power BI's
-- "Mark as date table" works with no extra conversion step, and BETWEEN
-- filters in SQL read like English.
--
-- Hints: HINTS.md D1.6
-- =============================================================================


BEGIN;
DROP TABLE IF EXISTS core.dim_date CASCADE;

-- D1. core.dim_date - one row per calendar day in the analysis window.
CREATE TABLE core.dim_date AS
WITH days AS (
    SELECT generate_series(DATE '2018-01-01', DATE '2021-12-31', INTERVAL '1 day')::date AS date_key
)
SELECT
    date_key,
    EXTRACT(YEAR    FROM date_key)::int                      AS year,
    EXTRACT(QUARTER FROM date_key)::int                      AS quarter_no,
    'Q' || EXTRACT(QUARTER FROM date_key)::int               AS quarter_name,
    EXTRACT(YEAR FROM date_key)::int || '-Q'
      || EXTRACT(QUARTER FROM date_key)::int                 AS year_quarter,
    EXTRACT(MONTH FROM date_key)::int                        AS month_no,      -- sort column
    to_char(date_key, 'Mon')                                 AS month_name,
    to_char(date_key, 'YYYY-MM')                             AS year_month,    -- sortable label
    -- Months since the start of the window: handy for cohort maths and for
    -- ordering a 48-month axis without string comparisons.
    ((EXTRACT(YEAR FROM date_key)::int - 2018) * 12
      + EXTRACT(MONTH FROM date_key)::int - 1)               AS month_index,
    EXTRACT(DAY FROM date_key)::int                          AS day_of_month,
    EXTRACT(ISODOW FROM date_key)::int                       AS day_of_week_no, -- 1 = Monday
    to_char(date_key, 'Dy')                                  AS day_of_week,
    (EXTRACT(ISODOW FROM date_key)::int >= 6)                AS is_weekend,
    date_trunc('month',   date_key)::date                    AS month_start,
    (date_trunc('month',  date_key) + INTERVAL '1 month - 1 day')::date AS month_end,
    date_trunc('quarter', date_key)::date                    AS quarter_start,
    date_trunc('year',    date_key)::date                    AS year_start,
    -- Flags the last complete year in the window, so "last year" in a query
    -- never depends on current_date. Nothing here is allowed to change
    -- meaning tomorrow.
    (EXTRACT(YEAR FROM date_key)::int = 2021)                AS is_latest_year
FROM days;

ALTER TABLE core.dim_date ADD PRIMARY KEY (date_key);

COMMENT ON TABLE core.dim_date IS
  'Contiguous calendar 2018-01-01 .. 2021-12-31 (1,461 rows). Built from generate_series, not from fact dates - a calendar with holes breaks time intelligence silently. Mark as date table in Power BI.';

COMMIT;

-- =============================================================================
-- CHECK - exactly 1,461 contiguous rows, no gaps, no nulls.
-- =============================================================================

SELECT
    count(*)                                                     AS rows,
    min(date_key)                                                AS first_day,
    max(date_key)                                                AS last_day,
    (max(date_key) - min(date_key) + 1)                          AS days_expected,
    count(*) - (max(date_key) - min(date_key) + 1)               AS gap_count,
    count(*) FILTER (WHERE month_no IS NULL OR year IS NULL)     AS null_attrs,
    CASE WHEN count(*) = 1461
          AND count(*) = (max(date_key) - min(date_key) + 1)
         THEN 'PASS' ELSE 'FAIL' END                             AS verdict
FROM core.dim_date;

-- Every fact date must exist in the calendar, or time intelligence drops rows.
SELECT count(*) AS fact_dates_missing_from_calendar
FROM (SELECT DISTINCT order_date FROM core.orders_clean) o
LEFT JOIN core.dim_date d ON d.date_key = o.order_date
WHERE d.date_key IS NULL;
