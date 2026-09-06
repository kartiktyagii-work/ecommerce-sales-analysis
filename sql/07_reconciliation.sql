-- =============================================================================
-- 07_reconciliation.sql - THE GATE. Do not proceed until every row says PASS.
-- =============================================================================
--   psql -h 127.0.0.1 -U postgres -d ecommerce -v ON_ERROR_STOP=1 -f sql/07_reconciliation.sql
--
-- Build this as ONE query returning:
--     metric | expected | actual | difference | verdict
--
-- Not five queries you eyeball. A gate you have to squint at is a gate you
-- wave through at hour seven when you are tired.
--
-- Metrics to tie: rows, sum(sales), sum(profit), sum(quantity),
-- distinct orders, distinct customers.
--
-- If something does not tie, the bug is in the last two hours of work and it
-- is cheap to find. Carry it forward and every number on every dashboard page
-- is wrong - and you discover that on Day 5 with no time left.
--
-- This is the gate that would have caught the mistake in Priya's email: the
-- last analyst counted returned orders as sales and told the board the wrong
-- region was the best one.
--
-- Hints: HINTS.md D1.8
-- =============================================================================


-- =============================================================================
-- G1. The reconciliation. One query, one row per metric, a verdict column.
-- =============================================================================

-- TODO


-- =============================================================================
-- G2. Return-rate sanity check - really a fan-out detector. Compute the
--     order-level return rate. If it is far higher than the returns file
--     suggested, you multiplied returns across order lines.
-- =============================================================================

-- TODO


-- =============================================================================
-- G3. Record the results in analysis/data-quality-log.md under
--     "Reconciliation record". Day 3's DAX gate checks against those numbers.
-- =============================================================================

