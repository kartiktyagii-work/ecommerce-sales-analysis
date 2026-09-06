-- =============================================================================
-- 01_staging_load.sql - raw CSV -> staging, EVERY COLUMN AS text
-- =============================================================================
--   psql -h 127.0.0.1 -U postgres -d ecommerce -v ON_ERROR_STOP=1 -f sql/01_staging_load.sql
--
-- Why all text: if you declare `sales numeric` and one row holds '1,234.56',
-- the whole load fails and you learn nothing about HOW MANY rows are bad.
-- Load as text, profile, then cast. The failure becomes data, not an error.
--
-- \copy is a psql CLIENT command. pgAdmin cannot run it. Server-side COPY
-- cannot read your Documents folder. Use \copy, from psql, always.
--
-- \copy maps columns BY POSITION, not by name. Your column order below must
-- match the CSV header order exactly.
--
-- Data: 02-Datasets/Raw/ecommerce-scaled/
-- Hints: HINTS.md D1.1
-- =============================================================================


BEGIN;

DROP TABLE IF EXISTS staging.orders, staging.returns, staging.targets;

-- T1. staging.orders - 21 columns, all text, in CSV header order.
--     Header: Row ID, Order ID, Order Date, Ship Date, Ship Mode, Customer ID,
--     Customer Name, Segment, Country/Region, City, State, Postal Code, Region,
--     Product ID, Category, Sub-Category, Product Name, Sales, Quantity,
--     Discount, Profit
-- TODO


-- T2. staging.returns - 2 columns.
-- TODO


-- T3. staging.targets - 5 columns. Open the file in a text editor first; the
--     header is not as clean as you would like, and that is the point.
-- TODO


COMMIT;

-- Load (run these from inside psql, adjusting paths if your checkout differs):
-- \copy staging.orders  FROM 'C:/Users/coral/Documents/PBI Dashboads/02-Datasets/Raw/ecommerce-scaled/orders.csv'  WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
-- \copy staging.returns FROM 'C:/Users/coral/Documents/PBI Dashboads/02-Datasets/Raw/ecommerce-scaled/returns.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
-- \copy staging.targets FROM 'C:/Users/coral/Documents/PBI Dashboads/02-Datasets/Raw/ecommerce-scaled/targets.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- =============================================================================
-- CHECK - row counts. Compare against `wc -l` on each file, minus the header.
-- =============================================================================

-- TODO
