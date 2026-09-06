-- =============================================================================
-- 16_discount_counterfactual.sql - The counterfactual
-- =============================================================================
-- Run these in pgAdmin - you want the grid. But KEEP THE QUERIES IN THIS FILE,
-- not in a scratch tab. These are a deliverable.
--
-- One query per question ID from analysis/questions.md (!...). Above each
-- query write the ID, the question in words, and your approach in one line.
--
-- Write every headline number into the Answer column of the register AS YOU GO.
-- Those numbers are what your DAX gets tested against on Day 3, and they are
-- the raw material for the Day 5 write-up.
-- =============================================================================
-- Written on DAY 3, after the change request. Not before.
--
-- "What would we have earned with discounts capped at X%?"
--
-- The naive answer recomputes profit for every line above the cap as though it
-- had been at the cap. Produce it - it is a fine first pass, and it is your
-- UPPER bound.
--
-- Then state the assumption you just made, because someone will attack it:
-- you assumed every one of those orders still happens at the lower discount.
-- That is certainly false. Some only converted BECAUSE of the discount.
--
-- You cannot observe price elasticity in this data. So bound it instead:
--   UPPER  every order survives the cap -> full margin recovery
--   LOWER  every order needing a discount above the cap is lost entirely,
--          taking its revenue AND its margin contribution with it
--   Your recommendation sits between them, and you say which assumption
--   drives it.
--
-- A range with a stated assumption is a senior answer. A point estimate here
-- is a guess in a suit.
--
-- Hints: HINTS.md D3.1
-- =============================================================================



-- !1 -
-- approach:
-- TODO


-- !2 -
-- approach:
-- TODO


-- !3 -
-- approach:
-- TODO
