-- =============================================================================
-- 03_cleaning.sql - staging (text) -> core (typed)
-- =============================================================================
--   psql -h 127.0.0.1 -U postgres -d ecommerce -v ON_ERROR_STOP=1 -f sql/03_cleaning.sql
--
-- You are IMPLEMENTING decisions already logged in
-- analysis/data-quality-log.md - not making new ones. If you find yourself
-- deciding something here, stop, go back, and log it first.
--
-- Three treatments, one per defect:
--   FIX        true value recoverable, nothing lost   (' West ' -> 'West')
--   QUARANTINE unusable row, must not vanish silently (-> core.rejected)
--   KEEP+FLAG  looks wrong, is real                   (negative profit!)
--
-- QUARANTINE, NEVER DELETE. `clean + rejected = staged` is a check you can
-- run. A WHERE clause is not.
--
-- Money casts to numeric, NEVER float. float gives you 1234.5600000000001 at
-- the reconciliation gate and twenty wasted minutes deciding whether a
-- rounding difference is a real problem.
--
-- Hints: HINTS.md D1.4
-- =============================================================================


BEGIN;

DROP TABLE IF EXISTS core.orders_clean, core.returns_clean, core.rejected;

-- =============================================================================
-- C1. core.rejected - same shape as staging.orders plus reject_reason.
--     The reason column is what makes the quarantine auditable.
-- =============================================================================

-- TODO


-- =============================================================================
-- C2. Classify and split. One pass that assigns a reject_reason (or NULL),
--     then routes rows to core.rejected or core.orders_clean, casting as it
--     goes. Empty string is not NULL: NULLIF(x, '').
-- =============================================================================

-- TODO


-- =============================================================================
-- C3. core.returns_clean. Mind the grain - check P8 before building this.
-- =============================================================================

-- TODO


COMMIT;

-- =============================================================================
-- CHECK - clean + rejected = staged, EXACTLY. Must return difference = 0.
-- =============================================================================

-- TODO


-- =============================================================================
-- CHECK - rejects grouped by reason. Every reason should be one you logged.
-- =============================================================================

-- TODO
