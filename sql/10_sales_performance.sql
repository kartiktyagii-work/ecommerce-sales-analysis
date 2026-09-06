-- =============================================================================
-- 10_sales_performance.sql - Sales performance
-- =============================================================================
-- Run these in pgAdmin - you want the grid. But KEEP THE QUERIES IN THIS FILE,
-- not in a scratch tab. These are a deliverable.
--
-- One query per question ID from analysis/questions.md (SP...). Above each
-- query write the ID, the question in words, and your approach in one line.
--
-- Write every headline number into the Answer column of the register AS YOU GO.
-- Those numbers are what your DAX gets tested against on Day 3, and they are
-- the raw material for the Day 5 write-up.
-- =============================================================================
-- Likely shapes (yours may differ - you wrote the register):
--   * totals, and how they move month over month and year over year
--   * average ORDER value. The fact table is at LINE grain, so collapse to
--     order grain in a CTE first. avg(sales) gives average LINE value, a
--     different and wrong number. The most common mistake on this dataset.
--   * seasonality - average the same calendar month ACROSS years. Ranking all
--     48 months just finds your biggest year, and revenue grows every year
--     here, so you would "discover" that 2021 is seasonal.
--   * what drove the gap between revenue growth and profit growth
--
-- Hints: HINTS.md D2.1, D2.2, D2.3
-- =============================================================================



-- SP1 -
-- approach:
-- TODO


-- SP2 -
-- approach:
-- TODO


-- SP3 -
-- approach:
-- TODO
