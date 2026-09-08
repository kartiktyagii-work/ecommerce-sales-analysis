-- =============================================================================
-- 05_dimensional_model.sql - the star schema
-- =============================================================================
--   psql -h 127.0.0.1 -U postgres -d ecommerce -v ON_ERROR_STOP=1 -f sql/05_dimensional_model.sql
--
-- Seven tables:
--   dim_date         (built in 04)          one row per calendar day
--   dim_customer     one row per customer_id
--   dim_product      one row per product_id
--   dim_geography    one row per country/region/state/city/postal_code
--   fact_order_line  LINE grain    - one row per product line on an order
--   fact_return      ORDER grain   - one row per returned order
--   fact_target      REGION-YEAR grain
--
-- Plus one supporting table, core.region_map, which is not part of the star:
-- it is the crosswalk that makes the messy targets file joinable.
--
-- -----------------------------------------------------------------------------
-- DECISION 1 - surrogate integer keys everywhere
-- -----------------------------------------------------------------------------
-- The natural keys here (customer_id 'KF-33865', product_id 'FUR-CH-10001802')
-- are stable text and would work. I used generated integers anyway because:
--   * a 1M-row fact joining on int4 beats one joining on 15-char text, and
--     Power BI's VertiPaq engine compresses integer columns far harder;
--   * dim_geography has no natural key at all - its identity is a five-column
--     composite - so it needs a surrogate regardless, and having one table
--     keyed differently from the rest is the kind of inconsistency that
--     produces a wrong join at 11pm.
-- The natural key is kept as an attribute on every dimension, so nothing is
-- lost and reconciliation back to staging is still a one-line join.
--
-- -----------------------------------------------------------------------------
-- DECISION 2 - geography hangs off the FACT, not off the customer
-- -----------------------------------------------------------------------------
-- Profiling found 77,779 customers with orders shipped to more than one city.
-- Location is therefore an attribute of the ORDER, not of the customer. Putting
-- it on dim_customer would force a "which one wins" rule and would silently
-- reassign historic revenue whenever a customer moved.
--
-- -----------------------------------------------------------------------------
-- DECISION 3 - fact_return is ORDER grain and carries its own measures
-- -----------------------------------------------------------------------------
-- This is the trap the whole project is built around. Returns are recorded per
-- ORDER; sales are recorded per LINE. Joining returns to lines multiplies every
-- return by that order's line count - which is exactly the bug in Priya's
-- email, where the last analyst told the board Central was the best region.
--
-- Two safeguards, belt and braces:
--   a) fact_return is built by aggregating lines to order grain FIRST and then
--      joining returns 1:1, so the returned order's revenue and profit are
--      stored once, additively. "Revenue lost to returns" becomes a plain SUM.
--   b) fact_order_line carries a denormalised is_returned boolean, computed
--      with EXISTS (which cannot fan out), so return rates can still be cut by
--      product and category - which order grain alone cannot do, because a
--      return is recorded against the whole order, not a line of it.
--
-- NEVER add SUM(fact_order_line.sales) to SUM(fact_return.order_sales). The
-- same money is in both, on purpose, at two different grains.
--
-- I considered a dim_order (an order-header dimension both facts hang off).
-- It is the more textbook answer and it is what I would build if returns ever
-- became line-level or gained their own attributes. At this size it buys a
-- table and an extra hop for no analytical gain.
--
-- Add PKs and FKs AFTER loading. A failing FK then is one clear error pointing
-- at a real data problem; added beforehand it just makes the inserts slow.
--
-- Hints: HINTS.md D1.5
-- =============================================================================


-- -----------------------------------------------------------------------------
-- PERFORMANCE NOTE - read this before you delete the SET and the ANALYZEs
-- -----------------------------------------------------------------------------
-- The first version of this script took over TEN MINUTES on the fact build and
-- I nearly accepted that as "1M rows is just slow". It was not. Two causes,
-- both worth knowing:
--
--   1. A table created by CREATE TABLE AS has NO planner statistics. The three
--      dimensions below are created and joined to in the same script, so at
--      join time the planner believed dim_customer held ONE row, chose a
--      nested loop, and re-scanned 107,688 rows for each of 996,567 fact rows.
--      Fix: ANALYZE each dimension the moment it exists. This is the single
--      highest-value line in the file.
--
--   2. work_mem defaults to 4MB. The hash table for dim_customer does not fit,
--      so the join spills to disk in batches. SET LOCAL raises it for this
--      transaction only and reverts at COMMIT - no server config change, no
--      side effects on anyone else.
--
-- Build time after both fixes: see analysis/query-tuning.md.
-- -----------------------------------------------------------------------------

BEGIN;

SET LOCAL work_mem = '256MB';

DROP TABLE IF EXISTS core.fact_order_line, core.fact_return, core.fact_target,
                     core.dim_customer, core.dim_product, core.dim_geography,
                     core.region_map CASCADE;

-- =============================================================================
-- M1. core.dim_customer - one row per customer_id.
--     Profiling proved customer_id -> exactly one name and one segment
--     (0 violations), so no "which description wins" rule is needed here.
--
--     customer_name_masked exists for the Legal request in the Day 3 change
--     request: outside Commercial, nobody sees a real customer name. RLS is
--     the primary control (see the .pbix); this column is the belt to that
--     brace, and it is what a portfolio reader sees when they open the file
--     with no role applied.
-- =============================================================================

CREATE TABLE core.dim_customer AS
SELECT
    row_number() OVER (ORDER BY customer_id)::int AS customer_key,
    customer_id,
    customer_name,
    segment,
    -- 'Claire Gute' + 'CG-12520' -> 'C. G. (CG-12520)'
    (SELECT string_agg(left(w, 1) || '.', ' ')
       FROM unnest(string_to_array(customer_name, ' ')) AS w)
      || ' (' || customer_id || ')'               AS customer_name_masked
FROM (
    SELECT customer_id,
           min(customer_name) AS customer_name,
           min(segment)       AS segment
    FROM core.orders_clean
    GROUP BY customer_id
) c;


-- =============================================================================
-- M2. core.dim_product - one row per product_id.
--     Profiling proved product_id -> one name, one category, one sub-category
--     (0 violations). If it had not, the rule would have been "most recent
--     description wins", logged in the DQ log before writing this.
-- =============================================================================

CREATE TABLE core.dim_product AS
SELECT
    row_number() OVER (ORDER BY product_id)::int AS product_key,
    product_id,
    product_name,
    category,
    sub_category
FROM (
    SELECT product_id,
           min(product_name) AS product_name,
           min(category)     AS category,
           min(sub_category) AS sub_category
    FROM core.orders_clean
    GROUP BY product_id
) p;


-- =============================================================================
-- M3. core.dim_geography - grain is a real decision.
--
--     Chosen grain: country + region + state + city + postal_code.
--     Why not postal_code alone: profiling found zip 92024 spanning Encinitas
--     and San Diego, so zip is not unique to a city, and 2,334 rows (Vermont)
--     have no zip at all - they would all collapse into one bogus location.
--     Why not city + state: that would merge the separate postal areas of a
--     large city and lose the finest geography the source actually has.
--     The 'UNKNOWN' postal code set in 03_cleaning keeps the Vermont rows
--     visible as their own locations rather than deleting or faking them.
-- =============================================================================

CREATE TABLE core.dim_geography AS
SELECT
    row_number() OVER (ORDER BY region, state, city, postal_code)::int AS geography_key,
    country, region, state, city, postal_code
FROM (
    SELECT DISTINCT country, region, state, city, postal_code
    FROM core.orders_clean
) g;


-- Statistics before the fact join - see the performance note at the top.
ANALYZE core.dim_customer;
ANALYZE core.dim_product;
ANALYZE core.dim_geography;


-- =============================================================================
-- M4. core.fact_order_line - LINE grain. Measures plus FKs.
--     order_id is kept as a degenerate dimension: it has no attributes of its
--     own worth a table, but AOV, order counts and the returns link all need
--     it.
-- =============================================================================

CREATE TABLE core.fact_order_line AS
SELECT
    o.order_line_key,
    o.order_id,                                   -- degenerate dimension
    o.order_date          AS date_key,            -- FK -> dim_date
    c.customer_key,                               -- FK -> dim_customer
    p.product_key,                                -- FK -> dim_product
    g.geography_key,                              -- FK -> dim_geography
    o.ship_date,
    o.ship_mode,
    o.ship_date_invalid,
    o.sales,
    o.quantity,
    o.discount,
    o.profit,
    o.gross_list_value,
    o.discount_value,
    o.is_loss_making,
    -- EXISTS, not JOIN. A join to a table with 3,045 duplicated order_ids
    -- would have doubled 3,045 orders' worth of lines before 03_cleaning
    -- deduped it, and EXISTS is immune either way. Semi-joins cannot fan out.
    EXISTS (SELECT 1 FROM core.returns_clean r WHERE r.order_id = o.order_id) AS is_returned
FROM core.orders_clean o
JOIN core.dim_customer  c ON c.customer_id = o.customer_id
JOIN core.dim_product   p ON p.product_id  = o.product_id
JOIN core.dim_geography g ON g.country     = o.country
                         AND g.region      = o.region
                         AND g.state       = o.state
                         AND g.city        = o.city
                         AND g.postal_code = o.postal_code;


ANALYZE core.fact_order_line;


-- =============================================================================
-- M5. core.fact_return - ORDER grain.
--     Lines are collapsed to order grain FIRST, then returns joined 1:1.
--     Do it the other way round and every measure below is multiplied by the
--     order's line count.
-- =============================================================================

CREATE TABLE core.fact_return AS
WITH order_totals AS (
    SELECT
        f.order_id,
        min(f.date_key)         AS date_key,
        min(f.customer_key)     AS customer_key,   -- one customer per order (proved in P2)
        min(f.geography_key)    AS geography_key,
        count(*)                AS order_lines,
        sum(f.sales)            AS order_sales,
        sum(f.profit)           AS order_profit,
        sum(f.quantity)         AS order_quantity
    FROM core.fact_order_line f
    GROUP BY f.order_id
)
SELECT
    t.order_id,
    t.date_key,
    t.customer_key,
    t.geography_key,
    t.order_lines,
    t.order_sales,
    t.order_profit,
    t.order_quantity,
    r.return_status
FROM core.returns_clean r
JOIN order_totals t USING (order_id);


-- =============================================================================
-- M6a. core.region_map - the crosswalk for the targets file.
--
--      Explicit mapping, not a fuzzy match. Explicit is defensible: Anand can
--      read this table and confirm it in thirty seconds. A trigram similarity
--      score cannot be confirmed by anyone, and silently maps 'Sth' to
--      whatever it feels like the day the data changes.
--      Every raw spelling seen in staging.targets is listed. The LEFT JOIN
--      check at the bottom of this file fails loudly if a new one appears.
-- =============================================================================

CREATE TABLE core.region_map (
    raw_region  text PRIMARY KEY,
    region      text NOT NULL
);

INSERT INTO core.region_map (raw_region, region) VALUES
    ('C',           'Central'),
    ('Central',     'Central'),
    ('central',     'Central'),
    ('CENTRAL',     'Central'),
    ('E',           'East'),
    ('East',        'East'),
    ('east',        'East'),
    ('EAST',        'East'),
    ('East Region', 'East'),
    ('S',           'South'),
    ('South',       'South'),
    ('south',       'South'),
    ('SOUTH',       'South'),
    ('Sth',         'South'),
    ('W',           'West'),
    ('West',        'West'),
    ('west',        'West'),
    ('WEST',        'West');


-- =============================================================================
-- M6b. core.fact_target - REGION-YEAR grain.
--
--      Three separate repairs, each logged in the DQ log:
--        * region spelling      -> region_map
--        * units column '000s'  -> multiply the target by 1,000
--        * duplicated rows      -> DISTINCT on the whole tuple, because the
--          duplicates are exact copies (EAST 2021 and West 2019). If they had
--          disagreed, that would be a question for Bhavna, not a DISTINCT.
--
--      What is deliberately NOT done: inventing the missing Central 2018
--      target. It stays absent, surfaces as "no target set" in 15_targets.sql,
--      and is itself a finding.
-- =============================================================================

CREATE TABLE core.fact_target AS
WITH typed AS (
    SELECT DISTINCT
        m.region,
        btrim(t.year)::int                             AS year,
        btrim(t.revenue_target)::numeric(16,2)         AS raw_target,
        NULLIF(btrim(t.units), '')                     AS units,
        NULLIF(btrim(t.owner), '')                     AS owner
    FROM staging.targets t
    JOIN core.region_map m ON m.raw_region = btrim(t.region)
)
SELECT
    region,
    year,
    CASE WHEN units = '000s' THEN raw_target * 1000 ELSE raw_target END::numeric(16,2)
                                                       AS revenue_target,
    raw_target                                         AS raw_target_as_supplied,
    coalesce(units, 'units')                           AS supplied_units,
    owner                                              AS supplied_owner
FROM typed;


-- =============================================================================
-- M7. Primary keys and foreign keys - added after load, on purpose.
-- =============================================================================

ALTER TABLE core.dim_customer   ADD PRIMARY KEY (customer_key);
ALTER TABLE core.dim_product    ADD PRIMARY KEY (product_key);
ALTER TABLE core.dim_geography  ADD PRIMARY KEY (geography_key);
ALTER TABLE core.fact_order_line ADD PRIMARY KEY (order_line_key);
ALTER TABLE core.fact_return    ADD PRIMARY KEY (order_id);
ALTER TABLE core.fact_target    ADD PRIMARY KEY (region, year);

ALTER TABLE core.dim_customer   ADD CONSTRAINT uq_dim_customer_nk  UNIQUE (customer_id);
ALTER TABLE core.dim_product    ADD CONSTRAINT uq_dim_product_nk   UNIQUE (product_id);
ALTER TABLE core.dim_geography  ADD CONSTRAINT uq_dim_geography_nk
    UNIQUE (country, region, state, city, postal_code);

ALTER TABLE core.fact_order_line
    ADD CONSTRAINT fk_fol_date      FOREIGN KEY (date_key)      REFERENCES core.dim_date(date_key),
    ADD CONSTRAINT fk_fol_customer  FOREIGN KEY (customer_key)  REFERENCES core.dim_customer(customer_key),
    ADD CONSTRAINT fk_fol_product   FOREIGN KEY (product_key)   REFERENCES core.dim_product(product_key),
    ADD CONSTRAINT fk_fol_geography FOREIGN KEY (geography_key) REFERENCES core.dim_geography(geography_key);

ALTER TABLE core.fact_return
    ADD CONSTRAINT fk_fr_date       FOREIGN KEY (date_key)      REFERENCES core.dim_date(date_key),
    ADD CONSTRAINT fk_fr_customer   FOREIGN KEY (customer_key)  REFERENCES core.dim_customer(customer_key),
    ADD CONSTRAINT fk_fr_geography  FOREIGN KEY (geography_key) REFERENCES core.dim_geography(geography_key);

COMMENT ON TABLE core.fact_order_line IS
  'LINE grain: one row per product line on one order. 996,567 rows. Additive: sales, quantity, profit, discount_value. NOT additive: discount (it is a rate - average it weighted, or recompute from discount_value / gross_list_value).';
COMMENT ON TABLE core.fact_return IS
  'ORDER grain: one row per returned order, carrying that order''s total sales and profit. Never add its measures to fact_order_line measures - the same money is in both at different grains.';
COMMENT ON TABLE core.fact_target IS
  'REGION-YEAR grain. Central 2018 is legitimately absent from the source and is left absent.';

COMMIT;

ANALYZE core.fact_order_line;
ANALYZE core.fact_return;
ANALYZE core.dim_customer;
ANALYZE core.dim_product;
ANALYZE core.dim_geography;


-- =============================================================================
-- CHECK - no orphans. Every FK in fact_order_line resolves. All must be 0.
--         (The FK constraints above would have refused to be created if not,
--          but this reports the number instead of an error - which is what
--          you want in a log you keep.)
-- =============================================================================

SELECT 'fact_order_line -> dim_date'      AS relationship,
       count(*) AS orphans FROM core.fact_order_line f
  LEFT JOIN core.dim_date d USING (date_key) WHERE d.date_key IS NULL
UNION ALL
SELECT 'fact_order_line -> dim_customer', count(*) FROM core.fact_order_line f
  LEFT JOIN core.dim_customer c USING (customer_key) WHERE c.customer_key IS NULL
UNION ALL
SELECT 'fact_order_line -> dim_product', count(*) FROM core.fact_order_line f
  LEFT JOIN core.dim_product p USING (product_key) WHERE p.product_key IS NULL
UNION ALL
SELECT 'fact_order_line -> dim_geography', count(*) FROM core.fact_order_line f
  LEFT JOIN core.dim_geography g USING (geography_key) WHERE g.geography_key IS NULL
UNION ALL
SELECT 'fact_return -> order in fact_order_line', count(*) FROM core.fact_return r
  WHERE NOT EXISTS (SELECT 1 FROM core.fact_order_line f WHERE f.order_id = r.order_id);


-- =============================================================================
-- CHECK - dimension grain. Each must be 0.
-- =============================================================================

SELECT 'dim_customer duplicate natural keys' AS check_name,
       count(*) - count(DISTINCT customer_id) AS violations FROM core.dim_customer
UNION ALL
SELECT 'dim_product duplicate natural keys',
       count(*) - count(DISTINCT product_id) FROM core.dim_product
UNION ALL
SELECT 'fact_target rows not one per region-year',
       count(*) - count(DISTINCT (region, year)) FROM core.fact_target;


-- =============================================================================
-- CHECK - every raw target region spelling was mapped. Must be 0 rows.
--         An unmapped spelling silently drops a whole region-year.
-- =============================================================================

SELECT btrim(t.region) AS unmapped_raw_region, count(*) AS rows
FROM staging.targets t
LEFT JOIN core.region_map m ON m.raw_region = btrim(t.region)
WHERE m.raw_region IS NULL
GROUP BY 1;


-- =============================================================================
-- CHECK - table sizes, for the record.
-- =============================================================================

SELECT 'dim_date' AS table_name, count(*) AS rows FROM core.dim_date
UNION ALL SELECT 'dim_customer',    count(*) FROM core.dim_customer
UNION ALL SELECT 'dim_product',     count(*) FROM core.dim_product
UNION ALL SELECT 'dim_geography',   count(*) FROM core.dim_geography
UNION ALL SELECT 'fact_order_line', count(*) FROM core.fact_order_line
UNION ALL SELECT 'fact_return',     count(*) FROM core.fact_return
UNION ALL SELECT 'fact_target',     count(*) FROM core.fact_target
ORDER BY 2 DESC;
