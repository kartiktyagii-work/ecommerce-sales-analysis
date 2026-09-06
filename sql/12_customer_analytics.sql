-- =============================================================================
-- 12_customer_analytics.sql - Customer analytics
-- =============================================================================
-- Run these in pgAdmin - you want the grid. But KEEP THE QUERIES IN THIS FILE,
-- not in a scratch tab. These are a deliverable.
--
-- One query per question ID from analysis/questions.md (CA...). Above each
-- query write the ID, the question in words, and your approach in one line.
--
-- Write every headline number into the Answer column of the register AS YOU GO.
-- Those numbers are what your DAX gets tested against on Day 3, and they are
-- the raw material for the Day 5 write-up.
-- =============================================================================
-- Likely shapes:
--   * active and unique customers, repeat rate, order frequency
--   * RFM via NTILE(5) on each of recency / frequency / monetary.
--     Recency INVERTS: bought yesterday should score 5, not 1.
--     Use a FIXED as-of date (data ends 2021-12-31), never current_date, or
--     nothing you compute will reproduce tomorrow.
--   * cohort retention: first-purchase month x months-since.
--     months_since = 0 must be 100% for every cohort - your correctness check.
--     Most expensive query in the sprint. Timebox to 45 min, cut on sight.
--
-- Hints: HINTS.md D2.8, D2.9
-- =============================================================================



-- CA1 -
-- approach:
-- TODO


-- CA2 -
-- approach:
-- TODO


-- CA3 -
-- approach:
-- TODO
