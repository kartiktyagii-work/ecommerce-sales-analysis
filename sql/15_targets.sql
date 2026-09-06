-- =============================================================================
-- 15_targets.sql - Target vs actual
-- =============================================================================
-- Run these in pgAdmin - you want the grid. But KEEP THE QUERIES IN THIS FILE,
-- not in a scratch tab. These are a deliverable.
--
-- One query per question ID from analysis/questions.md (TG...). Above each
-- query write the ID, the question in words, and your approach in one line.
--
-- Write every headline number into the Answer column of the register AS YOU GO.
-- Those numbers are what your DAX gets tested against on Day 3, and they are
-- the raw material for the Day 5 write-up.
-- =============================================================================
-- The second source, and a real integration problem. The targets file was
-- maintained by three different people and it shows.
--
-- Do NOT solve this with a fuzzy match. Build an explicit mapping table.
-- Explicit beats clever here because you can show it to Anand and he can
-- confirm it - which is what makes it defensible.
--
-- Three things to verify and log:
--   * every raw value mapped. LEFT JOIN and check for NULLs; an unmapped
--     spelling silently drops a whole region-year
--   * exactly one row per region-year after dedupe
--   * one region-year is genuinely missing. Do NOT invent it. Show it as
--     "no target set" - an honest gap beats a fabricated number, and noticing
--     it is itself a finding
--
-- Use FULL OUTER JOIN for target vs actual: it surfaces both "actual with no
-- target" and "target with no actual". INNER JOIN hides exactly what matters.
--
-- Hints: HINTS.md D2.11
-- =============================================================================



-- TG1 -
-- approach:
-- TODO


-- TG2 -
-- approach:
-- TODO


-- TG3 -
-- approach:
-- TODO
