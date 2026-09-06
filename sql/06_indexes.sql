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
-- Hints: HINTS.md D1.7
-- =============================================================================


-- =============================================================================
-- I1. Baseline. EXPLAIN (ANALYZE, BUFFERS) your slow query, before indexing.
-- =============================================================================

-- TODO


-- =============================================================================
-- I2. Indexes.
-- =============================================================================

-- TODO

-- ANALYZE core.fact_order_line;


-- =============================================================================
-- I3. After. The same EXPLAIN. Record the delta.
-- =============================================================================

-- TODO
