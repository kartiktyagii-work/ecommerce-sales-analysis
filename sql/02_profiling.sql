-- =============================================================================
-- 02_profiling.sql - find out what you actually have
-- =============================================================================
-- Read-only. You cannot break anything here. Run it in pgAdmin for the grid.
--
-- NOTHING IS PRE-WRITTEN, ON PURPOSE. An earlier version of this project
-- handed you 15 profiling queries and labelled which one was the trap. That is
-- a tutorial. Real profiling is hunting unknown unknowns, and that is the
-- skill this block exists to build.
--
-- Seven data-quality defects were injected from a menu of sixteen, at rates
-- between 0.04% and 0.6%. At ~1M rows that is 400-6,000 rows each: invisible
-- unless you count deliberately. You are not told which seven.
--
-- Method (not answers): HINTS.md D1.2, D1.3
-- =============================================================================


-- =============================================================================
-- P1. Shape. Row counts, and the date range actually present in the data.
-- =============================================================================

-- TODO


-- =============================================================================
-- P2. GRAIN. Does count(*) equal count(DISTINCT (order_id, product_id))?
--     If not: are the extras exact duplicates, or the same product
--     legitimately on one order twice? Those are different problems.
--     Write the answer into analysis/data-quality-log.md as a SENTENCE before
--     going further. Everything downstream depends on this being right.
-- =============================================================================

-- TODO


-- =============================================================================
-- P3. Column-level profile. All 21 columns at once: nulls, blanks, distinct
--     counts, min, max. Writing 21 separate queries is the slow way -
--     to_jsonb(row) + jsonb_each_text unpivots them in a single pass.
-- =============================================================================

-- TODO


-- =============================================================================
-- P4. Text hygiene. For each text column, does trim(lower(x)) have FEWER
--     distinct values than x? Any gap means values that should be identical
--     are not, and your GROUP BYs are silently splitting into phantom groups.
-- =============================================================================

-- TODO


-- =============================================================================
-- P5. Numeric sanity. Are the numeric-looking columns actually numeric?
--     Any values outside a physically possible range?
--     Test the SHAPE with a regex BEFORE you cast, or the query itself errors.
-- =============================================================================

-- TODO


-- =============================================================================
-- P6. Date sanity. All dates ISO-formatted? All in window? Any pair of
--     dates in an impossible order?
-- =============================================================================

-- TODO


-- =============================================================================
-- P7. Referential consistency. Does any business key map to more than one
--     description - one id, two names? This decides how you build dimensions.
-- =============================================================================

-- TODO


-- =============================================================================
-- P8. The returns file. Rows vs distinct order ids, and do all of them exist
--     in orders? The gap between those two numbers determines how you build
--     fact_return two files from now. Get this wrong and you find out on Day 4
--     as a return rate that is wildly too high.
-- =============================================================================

-- TODO


-- =============================================================================
-- P9. The targets file. Distinct spellings per region, duplicated
--     region-years, and whether every region-year you expect is present.
-- =============================================================================

-- TODO


-- =============================================================================
-- P10. Your own checks. Whatever the results above made you suspicious of.
--      This section is usually where the findings are.
-- =============================================================================

-- TODO
