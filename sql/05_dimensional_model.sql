-- =============================================================================
-- 05_dimensional_model.sql - the star schema
-- =============================================================================
--   psql -h 127.0.0.1 -U postgres -d ecommerce -v ON_ERROR_STOP=1 -f sql/05_dimensional_model.sql
--
-- Seven tables:
--   dim_date         (built in 04)
--   dim_customer     one row per customer
--   dim_product      one row per product
--   dim_geography    one row per distinct location   <- YOU decide the grain
--   fact_order_line  measures + foreign keys         <- what grain? prove it
--   fact_return                                      <- what grain? see P8
--   fact_target      regional revenue targets        <- what grain?
--
-- THE DIMENSION RULE: exactly one row per business entity. If P7 found a
-- business key mapping to two descriptions, you must pick one before the table
-- can exist. There is no single correct rule - most recent, most frequent,
-- longest - but there IS a requirement to decide it, log it, and be consistent.
--
-- Surrogate vs natural keys: the natural keys here (customer_id, product_id)
-- are stable text and defensible at this size. Surrogate integers are the
-- textbook choice and make Power BI relationships faster. Pick one, write down
-- why in the README, be consistent.
--
-- Add PKs and FKs AFTER loading. A failing FK then is one clear error pointing
-- at a real data problem; added beforehand it just makes the inserts slow.
--
-- Hints: HINTS.md D1.5
-- =============================================================================


BEGIN;

-- M1. core.dim_customer
-- TODO


-- M2. core.dim_product
-- TODO


-- M3. core.dim_geography - the grain here is a real decision. One row per
--     postal code, or per city + state? Blank postal codes force the issue.
-- TODO


-- M4. core.fact_order_line - measures plus FKs to date, customer, product and
--     geography. Keep order_id: it is a degenerate dimension, and fact_return
--     needs something to relate to.
-- TODO


-- M5. core.fact_return
-- TODO


-- M6. core.fact_target - from staging.targets. Needs a mapping table first;
--     see HINTS.md D2.11. Building it here is fine, or defer it to 15_.
-- TODO


-- M7. Primary keys and foreign keys.
-- TODO

COMMIT;

-- =============================================================================
-- CHECK - no orphans. Every FK in fact_order_line resolves. All must be 0.
-- =============================================================================

-- TODO
