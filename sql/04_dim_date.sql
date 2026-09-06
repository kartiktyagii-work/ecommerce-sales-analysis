-- =============================================================================
-- 04_dim_date.sql - the calendar
-- =============================================================================
--   psql -h 127.0.0.1 -U postgres -d ecommerce -v ON_ERROR_STOP=1 -f sql/04_dim_date.sql
--
-- Build from generate_series, NEVER from the dates present in the fact table.
-- A date table built from facts has a hole on every day with no orders, and
-- Power BI time intelligence then mis-computes across the gaps, silently.
--
-- Window: 2018-01-01 to 2021-12-31 -> 1,461 rows.
--
-- Include a NUMERIC month column alongside the month name. Power BI needs it
-- to sort Jan/Feb/Mar correctly instead of alphabetically (Apr, Aug, Dec...).
-- This catches everyone exactly once.
--
-- Hints: HINTS.md D1.6
-- =============================================================================


BEGIN;
DROP TABLE IF EXISTS core.dim_date CASCADE;

-- D1. core.dim_date - date_key, year, quarter, month_no, month_name,
--     year_month, day_of_week, is_weekend, plus anything your questions need.
-- TODO

COMMIT;

-- =============================================================================
-- CHECK - exactly 1,461 contiguous rows, no gaps, no nulls.
-- =============================================================================

-- TODO
