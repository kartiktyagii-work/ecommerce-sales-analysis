-- =============================================================================
-- 14_returns_analysis.sql - Returns
-- =============================================================================
-- Run these in pgAdmin - you want the grid. But KEEP THE QUERIES IN THIS FILE,
-- not in a scratch tab. These are a deliverable.
--
-- One query per question ID from analysis/questions.md (RT...). Above each
-- query write the ID, the question in words, and your approach in one line.
--
-- Write every headline number into the Answer column of the register AS YOU GO.
-- Those numbers are what your DAX gets tested against on Day 3, and they are
-- the raw material for the Day 5 write-up.
-- =============================================================================
-- fact_return is at ORDER grain. fact_order_line is at LINE grain.
-- Join them naively and every return multiplies by that order's line count.
-- Two safe patterns: collapse lines to order grain first, or use EXISTS.
--
-- Sanity-check every rate you compute against the overall rate from the Day 1
-- gate. A category rate far above it means you fanned out somewhere.
--
-- Likely shapes: overall rate, rate by category and region, revenue and profit
-- impact, and whether high-return lines are also top sellers.
--
-- Hints: HINTS.md D2.10
-- =============================================================================



-- RT1 -
-- approach:
-- TODO


-- RT2 -
-- approach:
-- TODO


-- RT3 -
-- approach:
-- TODO
