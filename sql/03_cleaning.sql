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
-- -----------------------------------------------------------------------------
-- DECISIONS IMPLEMENTED HERE (data-quality-log.md rows 1-9)
-- -----------------------------------------------------------------------------
--   #  Defect                                     Rows      Treatment
--   1  sales holds thousands separators           18        FIX  strip ','
--   2  region case / whitespace variants          2,298     FIX  btrim + initcap
--   3  postal_code lost its leading zero          118,407   FIX  lpad to 5
--   4  postal_code blank (all Vermont)            2,334     KEEP -> 'UNKNOWN'
--   5  row_id collapsed to '1'                    2,502     KEEP, drop the column
--   6  ship_date exactly 3 days before order_date 2,501     KEEP+FLAG, ship_date -> NULL
--   7  sales = 0 while quantity >= 1              4,002     QUARANTINE
--   8  same (order_id, product_id) twice          764 pairs KEEP - not duplicates
--   9  returns file repeats 3,045 order_ids       3,045     FIX  dedupe to order grain
--
-- Why #6 is KEEP+FLAG and #7 is QUARANTINE - this is the whole judgement:
--   #6 damages ONE column (ship_date) that no question in the register depends
--      on. Quarantining would throw away 2,501 rows of perfectly good revenue
--      to punish a column nobody reads. Null the column, flag the row, move on.
--   #7 damages the measure itself. sales = 0 with quantity >= 1 AND non-zero
--      profit is internally impossible: you cannot earn 113.67 of profit on
--      0.00 of revenue. The row is not "zero revenue", it is "revenue missing".
--      Keeping it understates revenue and puts a zero in the denominator of
--      every margin ratio. Out it goes - into quarantine, with a reason.
--
-- Hints: HINTS.md D1.4
-- =============================================================================


BEGIN;

DROP TABLE IF EXISTS core.orders_clean, core.returns_clean, core.rejected CASCADE;

-- =============================================================================
-- C1. core.rejected - same shape as staging.orders plus reject_reason.
--     The reason column is what makes the quarantine auditable: you can group
--     by it and show that every reason is one you logged.
-- =============================================================================

CREATE TABLE core.rejected (
    row_id          text,
    order_id        text,
    order_date      text,
    ship_date       text,
    ship_mode       text,
    customer_id     text,
    customer_name   text,
    segment         text,
    country_region  text,
    city            text,
    state           text,
    postal_code     text,
    region          text,
    product_id      text,
    category        text,
    sub_category    text,
    product_name    text,
    sales           text,
    quantity        text,
    discount        text,
    profit          text,
    reject_reason   text NOT NULL,
    rejected_at     timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE core.rejected IS
  'Quarantine. Rows that could not be trusted into core.orders_clean, kept verbatim with the reason. core.orders_clean + core.rejected must equal staging.orders exactly.';


-- =============================================================================
-- C2. Classify and split. ONE pass that assigns a reject_reason (or NULL),
--     then routes rows to core.rejected or core.orders_clean, casting as it
--     goes. Empty string is not NULL: NULLIF(x, '').
--
--     `classified` is materialised once and read twice so the two branches
--     cannot drift apart - which is exactly how rows go missing.
-- =============================================================================

CREATE TEMP TABLE classified ON COMMIT DROP AS
SELECT
    s.*,
    -- Parsed once here, reused by both branches.
    to_date(NULLIF(s.order_date, ''), 'FMMM/FMDD/YYYY')      AS p_order_date,
    to_date(NULLIF(s.ship_date , ''), 'FMMM/FMDD/YYYY')      AS p_ship_date,
    replace(NULLIF(s.sales, ''), ',', '')::numeric(14,4)     AS p_sales,     -- FIX #1
    NULLIF(s.quantity, '')::int                              AS p_quantity,
    NULLIF(s.discount, '')::numeric(6,4)                     AS p_discount,
    replace(NULLIF(s.profit, ''), ',', '')::numeric(14,4)    AS p_profit,
    CASE
        -- Order matters: first matching reason wins, most severe first.
        WHEN NULLIF(s.order_id, '')   IS NULL THEN 'missing_order_id'
        WHEN NULLIF(s.customer_id,'') IS NULL THEN 'missing_customer_id'
        WHEN NULLIF(s.product_id, '') IS NULL THEN 'missing_product_id'
        WHEN NULLIF(s.order_date, '') IS NULL THEN 'missing_order_date'
        WHEN replace(NULLIF(s.sales,''), ',', '')::numeric = 0
             AND NULLIF(s.quantity,'')::int >= 1
             THEN 'zero_sales_with_quantity'                                  -- QUARANTINE #7
        WHEN replace(NULLIF(s.sales,''), ',', '')::numeric < 0
             THEN 'negative_sales'
        WHEN NULLIF(s.quantity,'')::int <= 0 THEN 'non_positive_quantity'
        WHEN NULLIF(s.discount,'')::numeric < 0
          OR NULLIF(s.discount,'')::numeric > 1 THEN 'discount_out_of_range'
        ELSE NULL
    END AS reject_reason
FROM staging.orders s;


-- C2a. Quarantine branch - verbatim text, plus the reason.
INSERT INTO core.rejected (
    row_id, order_id, order_date, ship_date, ship_mode, customer_id, customer_name,
    segment, country_region, city, state, postal_code, region, product_id, category,
    sub_category, product_name, sales, quantity, discount, profit, reject_reason)
SELECT row_id, order_id, order_date, ship_date, ship_mode, customer_id, customer_name,
       segment, country_region, city, state, postal_code, region, product_id, category,
       sub_category, product_name, sales, quantity, discount, profit, reject_reason
FROM classified
WHERE reject_reason IS NOT NULL;


-- C2b. Clean branch - typed, normalised, flagged.
--      order_line_key is a generated surrogate. row_id from the source is NOT
--      usable as a key (defect #5: 2,502 rows all carry row_id = '1'), and it
--      carries no business meaning anyway, so it is kept only as a source
--      reference and never joined on.
CREATE TABLE core.orders_clean AS
SELECT
    row_number() OVER (ORDER BY p_order_date, order_id, product_id) AS order_line_key,
    row_id                                                   AS src_row_id,
    order_id,
    p_order_date                                             AS order_date,
    -- FLAG #6: a ship date before its order date is impossible. Null the value
    -- (so nobody computes a negative lead time from it) and keep the evidence
    -- in a boolean, so the row stays available for revenue analysis.
    CASE WHEN p_ship_date < p_order_date THEN NULL ELSE p_ship_date END AS ship_date,
    (p_ship_date < p_order_date)                             AS ship_date_invalid,
    btrim(ship_mode)                                         AS ship_mode,
    btrim(customer_id)                                       AS customer_id,
    btrim(customer_name)                                     AS customer_name,
    btrim(segment)                                           AS segment,
    btrim(country_region)                                    AS country,
    btrim(city)                                              AS city,
    btrim(state)                                             AS state,
    -- FIX #3 + KEEP #4: restore the leading zero on 4-digit codes; blank stays
    -- 'UNKNOWN' rather than becoming a fake zip. All 2,334 blanks are Vermont,
    -- which is how the original Superstore extract ships - not damage.
    CASE
        WHEN NULLIF(btrim(postal_code), '') IS NULL THEN 'UNKNOWN'
        ELSE lpad(btrim(postal_code), 5, '0')
    END                                                      AS postal_code,
    -- FIX #2: ' WEST ' / 'west' / 'West' are one region, not three.
    initcap(btrim(region))                                   AS region,
    btrim(product_id)                                        AS product_id,
    btrim(category)                                          AS category,
    btrim(sub_category)                                      AS sub_category,
    btrim(product_name)                                      AS product_name,
    p_sales                                                  AS sales,
    p_quantity                                               AS quantity,
    p_discount                                               AS discount,
    p_profit                                                 AS profit,
    -- Derived once here so every downstream query agrees on the definition.
    -- Gross list value implied by the discount: sales = list * (1 - discount).
    CASE WHEN p_discount < 1
         THEN round(p_sales / (1 - p_discount), 4) END       AS gross_list_value,
    CASE WHEN p_discount < 1
         THEN round(p_sales / (1 - p_discount) - p_sales, 4) END AS discount_value,
    (p_profit < 0)                                           AS is_loss_making   -- KEEP+FLAG
FROM classified
WHERE reject_reason IS NULL;


-- =============================================================================
-- C3. core.returns_clean. Mind the grain - P8 showed 30,727 rows covering only
--     27,682 distinct order_ids, i.e. 3,045 orders appear twice. A return is
--     an event on an ORDER. Two identical 'Yes' rows for one order is the file
--     being appended to twice, not the order being returned twice.
--
--     DISTINCT here is the entire defence against the fan-out Priya describes
--     in her email: the previous analyst joined this file straight to order
--     lines and every returned order multiplied by its line count.
-- =============================================================================

CREATE TABLE core.returns_clean AS
SELECT DISTINCT
    btrim(r.order_id)      AS order_id,
    btrim(r.return_status) AS return_status
FROM staging.returns r
WHERE NULLIF(btrim(r.order_id), '') IS NOT NULL;

COMMENT ON TABLE core.returns_clean IS
  'ORDER grain: exactly one row per returned order_id. Never join this to an order-line table without aggregating first - see 14_returns_analysis.sql.';

COMMIT;

-- =============================================================================
-- C4. Statistics. A table created by CREATE TABLE AS has NO planner
--     statistics until it is analysed. Join to it in the next script and the
--     planner assumes it holds one row, picks a nested loop, and a five-second
--     build turns into a five-minute one. Found this the hard way in
--     05_dimensional_model.sql - see analysis/query-tuning.md.
-- =============================================================================

ANALYZE core.orders_clean;
ANALYZE core.returns_clean;
ANALYZE core.rejected;

CREATE INDEX IF NOT EXISTS ix_orders_clean_order   ON core.orders_clean (order_id);
CREATE INDEX IF NOT EXISTS ix_orders_clean_cust    ON core.orders_clean (customer_id);
CREATE INDEX IF NOT EXISTS ix_orders_clean_prod    ON core.orders_clean (product_id);
CREATE INDEX IF NOT EXISTS ix_returns_clean_order  ON core.returns_clean (order_id);


-- =============================================================================
-- CHECK - clean + rejected = staged, EXACTLY. Must return difference = 0.
-- =============================================================================

SELECT
    (SELECT count(*) FROM staging.orders)     AS staged,
    (SELECT count(*) FROM core.orders_clean)  AS clean,
    (SELECT count(*) FROM core.rejected)      AS rejected,
    (SELECT count(*) FROM staging.orders)
      - (SELECT count(*) FROM core.orders_clean)
      - (SELECT count(*) FROM core.rejected)  AS difference;


-- =============================================================================
-- CHECK - rejects grouped by reason. Every reason should be one you logged.
-- =============================================================================

SELECT reject_reason,
       count(*)                                                          AS rows,
       round(100.0 * count(*) / (SELECT count(*) FROM staging.orders), 4) AS pct_of_staged
FROM core.rejected
GROUP BY reject_reason
ORDER BY rows DESC;


-- =============================================================================
-- CHECK - the fixes actually fired.
-- =============================================================================

SELECT 'distinct regions after normalisation' AS check_name, count(DISTINCT region)::text AS value FROM core.orders_clean
UNION ALL SELECT 'postal codes not 5 chars',  count(*)::text FROM core.orders_clean WHERE length(postal_code) <> 5 AND postal_code <> 'UNKNOWN'
UNION ALL SELECT 'ship_date_invalid flagged', count(*)::text FROM core.orders_clean WHERE ship_date_invalid
UNION ALL SELECT 'loss-making rows kept',     count(*)::text FROM core.orders_clean WHERE is_loss_making
UNION ALL SELECT 'returns deduped to orders', count(*)::text FROM core.returns_clean;
