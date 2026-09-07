-- =============================================================================
-- 02_profiling.sql - find out what you actually have
-- =============================================================================
--
-- Read-only profiling and data-quality investigation.
--
-- Purpose:
--   1. Understand the shape of the staged datasets.
--   2. Establish the grain of orders.
--   3. Identify NULLs, blanks, suspicious values and duplicates.
--   4. Validate numeric/date/text fields before transformation.
--   5. Check relationships between orders, returns and targets.
--   6. Produce evidence for analysis/data-quality-log.md.
--
-- IMPORTANT:
--   This script DOES NOT clean or modify the staging data.
--   It only reads and reports.
--
-- Run in pgAdmin or psql after 01_staging_load.sql.
--
-- Seven data-quality defects were injected from a menu of sixteen.
-- The purpose of this script is to discover them rather than assume them.
-- =============================================================================


-- =============================================================================
-- P1. SHAPE
--
-- Question:
--   How many rows do we actually have?
--   What date range is actually present?
--
-- Expected source sizes:
--   orders  = approximately 1,000,000+
--   returns = 30,000
--   targets = 18
-- =============================================================================

-- Orders row count + date range
SELECT
    'orders' AS dataset,
    COUNT(*) AS row_count,
    MIN(order_date) AS min_order_date,
    MAX(order_date) AS max_order_date,
    MIN(ship_date) AS min_ship_date,
    MAX(ship_date) AS max_ship_date
FROM staging.orders;


-- Returns row count
SELECT
    'returns' AS dataset,
    COUNT(*) AS row_count
FROM staging.returns;


-- Targets row count
SELECT
    'targets' AS dataset,
    COUNT(*) AS row_count
FROM staging.targets;


-- Combined shape summary
SELECT
    'orders' AS dataset,
    COUNT(*) AS row_count
FROM staging.orders

UNION ALL

SELECT
    'returns',
    COUNT(*)
FROM staging.returns

UNION ALL

SELECT
    'targets',
    COUNT(*)
FROM staging.targets;


-- =============================================================================
-- P2. GRAIN
--
-- Question:
--   Is one row really one order/product combination?
--
-- First compare:
--
--   COUNT(*)
--   COUNT(DISTINCT (order_id, product_id))
--
-- If these differ, investigate the repeated combinations.
-- Do NOT assume that repeated combinations are necessarily bad data.
-- =============================================================================

-- Basic grain comparison
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT (order_id, product_id)) AS distinct_order_product_pairs,
    COUNT(*) -
        COUNT(DISTINCT (order_id, product_id)) AS excess_rows
FROM staging.orders;


-- Show repeated order/product combinations
SELECT
    order_id,
    product_id,
    COUNT(*) AS occurrences
FROM staging.orders
GROUP BY
    order_id,
    product_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC, order_id, product_id;


-- Determine whether repeated order/product combinations are exact duplicates
--
-- The following compares all 21 source columns.
--
-- If a repeated pair has only one distinct row fingerprint, it is an
-- exact duplicate.
-- If it has multiple fingerprints, the same order/product pair contains
-- different information.
WITH duplicate_pairs AS (
    SELECT
        order_id,
        product_id
    FROM staging.orders
    GROUP BY
        order_id,
        product_id
    HAVING COUNT(*) > 1
),
fingerprinted AS (
    SELECT
        o.order_id,
        o.product_id,
        md5(
            concat_ws(
                '||',
                o.order_id,
                o.order_date,
                o.ship_date,
                o.ship_mode,
                o.customer_id,
                o.customer_name,
                o.segment,
                o.country_region,
                o.city,
                o.state,
                o.postal_code,
                o.region,
                o.product_id,
                o.category,
                o.sub_category,
                o.product_name,
                o.sales,
                o.quantity,
                o.discount,
                o.profit
            )
        ) AS row_fingerprint
    FROM staging.orders o
    INNER JOIN duplicate_pairs d
        ON o.order_id = d.order_id
       AND o.product_id = d.product_id
)
SELECT
    order_id,
    product_id,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT row_fingerprint) AS distinct_row_versions,
    CASE
        WHEN COUNT(DISTINCT row_fingerprint) = 1
            THEN 'EXACT_DUPLICATE'
        ELSE 'MULTIPLE_VERSIONS'
    END AS duplicate_type
FROM fingerprinted
GROUP BY
    order_id,
    product_id
ORDER BY
    total_rows DESC;


-- Summary of duplicate types
WITH duplicate_pairs AS (
    SELECT
        order_id,
        product_id
    FROM staging.orders
    GROUP BY
        order_id,
        product_id
    HAVING COUNT(*) > 1
),
fingerprinted AS (
    SELECT
        o.order_id,
        o.product_id,
        md5(
            concat_ws(
                '||',
                o.row_id,
                o.order_id,
                o.order_date,
                o.ship_date,
                o.ship_mode,
                o.customer_id,
                o.customer_name,
                o.segment,
                o.country_region,
                o.city,
                o.state,
                o.postal_code,
                o.region,
                o.product_id,
                o.category,
                o.sub_category,
                o.product_name,
                o.sales,
                o.quantity,
                o.discount,
                o.profit
            )
        ) AS row_fingerprint
    FROM staging.orders o
    INNER JOIN duplicate_pairs d
        ON o.order_id = d.order_id
       AND o.product_id = d.product_id
),
classified AS (
    SELECT
        order_id,
        product_id,
        CASE
            WHEN COUNT(DISTINCT row_fingerprint) = 1
                THEN 'EXACT_DUPLICATE'
            ELSE 'MULTIPLE_VERSIONS'
        END AS duplicate_type
    FROM fingerprinted
    GROUP BY
        order_id,
        product_id
)
SELECT
    duplicate_type,
    COUNT(*) AS order_product_pairs
FROM classified
GROUP BY
    duplicate_type
ORDER BY
    duplicate_type;


-- =============================================================================
-- P3. COLUMN-LEVEL PROFILE
--
-- Profile all 21 source columns at once:
--
--   total rows
--   NULL count
--   blank count
--   distinct values
--   minimum value
--   maximum value
--
-- JSONB is used to unpivot each row into:
--
--   column_name | value
--
-- so we don't need 21 separate queries.
-- =============================================================================

SELECT
    j.key AS column_name,

    COUNT(*) AS total_rows,

    COUNT(*) FILTER (
        WHERE j.value IS NULL
    ) AS null_count,

    COUNT(*) FILTER (
        WHERE j.value IS NOT NULL
          AND trim(j.value) = ''
    ) AS blank_count,

    COUNT(DISTINCT j.value) AS distinct_count,

    MIN(j.value) AS min_value,

    MAX(j.value) AS max_value

FROM staging.orders AS o
CROSS JOIN LATERAL
    jsonb_each_text(
        to_jsonb(o)
    ) AS j(key, value)

WHERE j.key NOT IN (
    '_source_file',
    '_loaded_at',
    '_load_id'
)

GROUP BY
    j.key

ORDER BY
    j.key;


-- =============================================================================
-- P4. TEXT HYGIENE
--
-- Question:
--   Does trim(lower(value)) produce fewer distinct values than the raw value?
--
-- If:
--
--   raw distinct      = 10
--   normalized        = 8
--
-- then multiple raw representations collapse into the same normalized value.
--
-- This can indicate:
--
--   "Technology"
--   "technology"
--   " TECHNOLOGY "
--
-- which can silently split GROUP BY results.
--
-- We explicitly profile the major categorical/text columns.
-- =============================================================================

WITH column_values AS (

    SELECT
        'ship_mode' AS column_name,
        ship_mode AS value
    FROM staging.orders

    UNION ALL

    SELECT
        'customer_name',
        customer_name
    FROM staging.orders

    UNION ALL

    SELECT
        'segment',
        segment
    FROM staging.orders

    UNION ALL

    SELECT
        'country_region',
        country_region
    FROM staging.orders

    UNION ALL

    SELECT
        'city',
        city
    FROM staging.orders

    UNION ALL

    SELECT
        'state',
        state
    FROM staging.orders

    UNION ALL

    SELECT
        'region',
        region
    FROM staging.orders

    UNION ALL

    SELECT
        'category',
        category
    FROM staging.orders

    UNION ALL

    SELECT
        'sub_category',
        sub_category
    FROM staging.orders

    UNION ALL

    SELECT
        'product_name',
        product_name
    FROM staging.orders
)

SELECT
    column_name,

    COUNT(DISTINCT value) AS raw_distinct_values,

    COUNT(
        DISTINCT trim(lower(value))
    ) AS normalized_distinct_values,

    COUNT(DISTINCT value)
        -
    COUNT(DISTINCT trim(lower(value)))
        AS phantom_distinct_values

FROM column_values

GROUP BY
    column_name

ORDER BY
    phantom_distinct_values DESC,
    column_name;


-- Show actual suspicious text variants
WITH normalized AS (
    SELECT
        category AS raw_value,
        trim(lower(category)) AS normalized_value
    FROM staging.orders
    WHERE category IS NOT NULL
)
SELECT
    normalized_value,
    COUNT(DISTINCT raw_value) AS raw_variations,
    STRING_AGG(
        DISTINCT quote_literal(raw_value),
        ', '
        ORDER BY quote_literal(raw_value)
    ) AS raw_values
FROM normalized
GROUP BY normalized_value
HAVING COUNT(DISTINCT raw_value) > 1
ORDER BY raw_variations DESC, normalized_value;


-- Repeat the same investigation for region
WITH normalized AS (
    SELECT
        region AS raw_value,
        trim(lower(region)) AS normalized_value
    FROM staging.orders
    WHERE region IS NOT NULL
)
SELECT
    normalized_value,
    COUNT(DISTINCT raw_value) AS raw_variations,
    STRING_AGG(
        DISTINCT quote_literal(raw_value),
        ', '
        ORDER BY quote_literal(raw_value)
    ) AS raw_values
FROM normalized
GROUP BY normalized_value
HAVING COUNT(DISTINCT raw_value) > 1
ORDER BY raw_variations DESC, normalized_value;


-- =============================================================================
-- P5. NUMERIC SANITY
--
-- Staging columns are TEXT.
--
-- NEVER cast blindly:
--
--   sales::numeric
--
-- because one malformed value can make the entire query fail.
--
-- First test the shape with a regular expression.
-- Then inspect ranges only for values that are structurally numeric.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- P5.1 Numeric shape
-- ---------------------------------------------------------------------------

SELECT
    'sales' AS column_name,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (
        WHERE sales IS NOT NULL
          AND trim(sales) <> ''
          AND sales !~ '^-?[0-9]+(\.[0-9]+)?$'
    ) AS invalid_numeric_rows
FROM staging.orders

UNION ALL

SELECT
    'quantity',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE quantity IS NOT NULL
          AND trim(quantity) <> ''
          AND quantity !~ '^-?[0-9]+$'
    )
FROM staging.orders

UNION ALL

SELECT
    'discount',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE discount IS NOT NULL
          AND trim(discount) <> ''
          AND discount !~ '^-?[0-9]+(\.[0-9]+)?$'
    )
FROM staging.orders

UNION ALL

SELECT
    'profit',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE profit IS NOT NULL
          AND trim(profit) <> ''
          AND profit !~ '^-?[0-9]+(\.[0-9]+)?$'
    )
FROM staging.orders;


-- ---------------------------------------------------------------------------
-- P5.2 Invalid numeric values - inspect the actual records
-- ---------------------------------------------------------------------------

SELECT
    sales
FROM staging.orders
WHERE sales IS NOT NULL
  AND trim(sales) <> ''
  AND sales !~ '^-?[0-9]+(\.[0-9]+)?$'
GROUP BY sales
ORDER BY sales;


SELECT
    quantity
FROM staging.orders
WHERE quantity IS NOT NULL
  AND trim(quantity) <> ''
  AND quantity !~ '^-?[0-9]+$'
GROUP BY quantity
ORDER BY quantity;


SELECT
    discount
FROM staging.orders
WHERE discount IS NOT NULL
  AND trim(discount) <> ''
  AND discount !~ '^-?[0-9]+(\.[0-9]+)?$'
GROUP BY discount
ORDER BY discount;


SELECT
    profit
FROM staging.orders
WHERE profit IS NOT NULL
  AND trim(profit) <> ''
  AND profit !~ '^-?[0-9]+(\.[0-9]+)?$'
GROUP BY profit
ORDER BY profit;


-- ---------------------------------------------------------------------------
-- P5.3 Physically/business suspicious numeric ranges
-- ---------------------------------------------------------------------------

-- Quantity should normally be positive.
SELECT
    COUNT(*) AS invalid_quantity_rows
FROM staging.orders
WHERE quantity ~ '^-?[0-9]+$'
  AND quantity::numeric <= 0;


-- Discount should normally be between 0 and 1.
SELECT
    COUNT(*) AS invalid_discount_rows
FROM staging.orders
WHERE discount ~ '^-?[0-9]+(\.[0-9]+)?$'
  AND (
        discount::numeric < 0
        OR discount::numeric > 1
      );


-- Sales should normally not be negative.
SELECT
    COUNT(*) AS negative_sales_rows
FROM staging.orders
WHERE sales ~ '^-?[0-9]+(\.[0-9]+)?$'
  AND sales::numeric < 0;


-- Inspect suspicious quantity values.
SELECT
    quantity,
    COUNT(*) AS occurrences
FROM staging.orders
WHERE quantity ~ '^-?[0-9]+$'
  AND quantity::numeric <= 0
GROUP BY quantity
ORDER BY quantity;


-- Inspect suspicious discounts.
SELECT
    discount,
    COUNT(*) AS occurrences
FROM staging.orders
WHERE discount ~ '^-?[0-9]+(\.[0-9]+)?$'
  AND (
        discount::numeric < 0
        OR discount::numeric > 1
      )
GROUP BY discount
ORDER BY discount;


-- =============================================================================
-- P6. DATE SANITY
--
-- Questions:
--
--   1. Are dates ISO formatted?
--   2. Are dates valid?
--   3. Are dates inside a sensible window?
--   4. Is order_date <= ship_date?
--
-- Again, validate shape BEFORE casting.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- P6.1 Date format
-- ---------------------------------------------------------------------------

SELECT
    'order_date' AS column_name,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (
        WHERE order_date IS NOT NULL
          AND trim(order_date) <> ''
          AND order_date !~ '^\d{4}-\d{2}-\d{2}$'
    ) AS invalid_format_rows
FROM staging.orders

UNION ALL

SELECT
    'ship_date',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE ship_date IS NOT NULL
          AND trim(ship_date) <> ''
          AND ship_date !~ '^\d{4}-\d{2}-\d{2}$'
    )
FROM staging.orders;


-- ---------------------------------------------------------------------------
-- P6.2 Invalid date values
-- ---------------------------------------------------------------------------

SELECT
    order_date,
    COUNT(*) AS occurrences
FROM staging.orders
WHERE order_date IS NOT NULL
  AND trim(order_date) <> ''
  AND order_date !~ '^\d{4}-\d{2}-\d{2}$'
GROUP BY order_date
ORDER BY occurrences DESC;


SELECT
    ship_date,
    COUNT(*) AS occurrences
FROM staging.orders
WHERE ship_date IS NOT NULL
  AND trim(ship_date) <> ''
  AND ship_date !~ '^\d{4}-\d{2}-\d{2}$'
GROUP BY ship_date
ORDER BY occurrences DESC;


-- ---------------------------------------------------------------------------
-- P6.3 Date range
--
-- Safe because only ISO-shaped values are cast.
-- ---------------------------------------------------------------------------

SELECT
    MIN(order_date::date) AS min_order_date,
    MAX(order_date::date) AS max_order_date,
    MIN(ship_date::date) AS min_ship_date,
    MAX(ship_date::date) AS max_ship_date
FROM staging.orders
WHERE order_date ~ '^\d{4}-\d{2}-\d{2}$'
  AND ship_date ~ '^\d{4}-\d{2}-\d{2}$';


-- ---------------------------------------------------------------------------
-- P6.4 Impossible order/ship dates
-- ---------------------------------------------------------------------------

SELECT
    COUNT(*) AS impossible_date_order_rows
FROM staging.orders
WHERE order_date ~ '^\d{4}-\d{2}-\d{2}$'
  AND ship_date ~ '^\d{4}-\d{2}-\d{2}$'
  AND order_date::date > ship_date::date;


-- Inspect those records
SELECT
    row_id,
    order_id,
    order_date,
    ship_date
FROM staging.orders
WHERE order_date ~ '^\d{4}-\d{2}-\d{2}$'
  AND ship_date ~ '^\d{4}-\d{2}-\d{2}$'
  AND order_date::date > ship_date::date
ORDER BY order_date, ship_date;


-- =============================================================================
-- P7. REFERENTIAL / BUSINESS-KEY CONSISTENCY
--
-- Question:
--   Does one business key consistently map to one description?
--
-- Examples:
--
--   customer_id -> customer_name
--   product_id  -> product_name
--   product_id  -> category
--   product_id  -> sub_category
--
-- If one ID maps to multiple descriptions, dimension construction becomes
-- ambiguous.
-- =============================================================================


-- Customer ID -> customer name
SELECT
    customer_id,
    COUNT(DISTINCT customer_name) AS distinct_customer_names,
    STRING_AGG(
        DISTINCT customer_name,
        ' | '
        ORDER BY customer_name
    ) AS customer_names
FROM staging.orders
WHERE customer_id IS NOT NULL
GROUP BY customer_id
HAVING COUNT(DISTINCT customer_name) > 1
ORDER BY distinct_customer_names DESC;


-- Product ID -> product name
SELECT
    product_id,
    COUNT(DISTINCT product_name) AS distinct_product_names,
    STRING_AGG(
        DISTINCT product_name,
        ' | '
        ORDER BY product_name
    ) AS product_names
FROM staging.orders
WHERE product_id IS NOT NULL
GROUP BY product_id
HAVING COUNT(DISTINCT product_name) > 1
ORDER BY distinct_product_names DESC;


-- Product ID -> category
SELECT
    product_id,
    COUNT(DISTINCT category) AS distinct_categories,
    STRING_AGG(
        DISTINCT category,
        ' | '
        ORDER BY category
    ) AS categories
FROM staging.orders
WHERE product_id IS NOT NULL
GROUP BY product_id
HAVING COUNT(DISTINCT category) > 1
ORDER BY distinct_categories DESC;


-- Product ID -> sub-category
SELECT
    product_id,
    COUNT(DISTINCT sub_category) AS distinct_sub_categories,
    STRING_AGG(
        DISTINCT sub_category,
        ' | '
        ORDER BY sub_category
    ) AS sub_categories
FROM staging.orders
WHERE product_id IS NOT NULL
GROUP BY product_id
HAVING COUNT(DISTINCT sub_category) > 1
ORDER BY distinct_sub_categories DESC;


-- =============================================================================
-- P8. RETURNS
--
-- Questions:
--
--   1. How many rows?
--   2. How many distinct order IDs?
--   3. Are any return order IDs duplicated?
--   4. Do all returned orders exist in orders?
-- =============================================================================


-- Basic returns profile
SELECT
    COUNT(*) AS total_return_rows,
    COUNT(DISTINCT order_id) AS distinct_return_order_ids,
    COUNT(*) -
        COUNT(DISTINCT order_id) AS duplicate_return_rows
FROM staging.returns;


-- Repeated return order IDs
SELECT
    order_id,
    COUNT(*) AS occurrences
FROM staging.returns
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC, order_id;


-- Return order IDs that do not exist in orders
SELECT
    COUNT(*) AS orphan_return_order_ids
FROM (
    SELECT DISTINCT r.order_id
    FROM staging.returns r
    WHERE r.order_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM staging.orders o
          WHERE o.order_id = r.order_id
      )
) x;


-- Inspect orphan return IDs
SELECT
    r.order_id,
    COUNT(*) AS return_rows
FROM staging.returns r
WHERE r.order_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM staging.orders o
      WHERE o.order_id = r.order_id
  )
GROUP BY r.order_id
ORDER BY return_rows DESC, r.order_id;


-- Return status domain
SELECT
    return_status,
    COUNT(*) AS occurrences
FROM staging.returns
GROUP BY return_status
ORDER BY occurrences DESC, return_status;


-- =============================================================================
-- P9. TARGETS
--
-- Questions:
--
--   1. How many distinct regions?
--   2. Are region spellings consistent?
--   3. Are region/year combinations unique?
--   4. Are expected region/year combinations present?
-- =============================================================================


-- Basic targets profile
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT region) AS distinct_regions,
    COUNT(DISTINCT year) AS distinct_years,
    COUNT(DISTINCT (region, year)) AS distinct_region_years
FROM staging.targets;


-- Region spellings
SELECT
    trim(lower(region)) AS normalized_region,
    COUNT(DISTINCT region) AS raw_variations,
    STRING_AGG(
        DISTINCT quote_literal(region),
        ', '
        ORDER BY quote_literal(region)
    ) AS raw_region_values
FROM staging.targets
WHERE region IS NOT NULL
GROUP BY trim(lower(region))
HAVING COUNT(DISTINCT region) > 1
ORDER BY raw_variations DESC;


-- Duplicate region/year combinations
SELECT
    region,
    year,
    COUNT(*) AS occurrences
FROM staging.targets
GROUP BY
    region,
    year
HAVING COUNT(*) > 1
ORDER BY occurrences DESC, region, year;


-- Target numeric shape
SELECT
    'year' AS column_name,
    COUNT(*) FILTER (
        WHERE year IS NOT NULL
          AND trim(year) <> ''
          AND year !~ '^\d{4}$'
    ) AS invalid_rows
FROM staging.targets

UNION ALL

SELECT
    'revenue_target',
    COUNT(*) FILTER (
        WHERE revenue_target IS NOT NULL
          AND trim(revenue_target) <> ''
          AND revenue_target !~ '^-?[0-9]+(\.[0-9]+)?$'
    )
FROM staging.targets

UNION ALL

SELECT
    'units',
    COUNT(*) FILTER (
        WHERE units IS NOT NULL
          AND trim(units) <> ''
          AND units !~ '^-?[0-9]+$'
    )
FROM staging.targets;


-- =============================================================================
-- P10. YOUR OWN CHECKS
--
-- These are intentionally additional investigative checks.
--
-- They are useful for discovering anomalies that may not fit neatly into
-- P1-P9.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- P10.1 Order ID -> customer consistency
--
-- One order should normally belong to one customer.
-- ---------------------------------------------------------------------------

SELECT
    order_id,
    COUNT(DISTINCT customer_id) AS distinct_customers,
    STRING_AGG(
        DISTINCT customer_id,
        ' | '
        ORDER BY customer_id
    ) AS customer_ids
FROM staging.orders
WHERE order_id IS NOT NULL
GROUP BY order_id
HAVING COUNT(DISTINCT customer_id) > 1
ORDER BY distinct_customers DESC;


-- ---------------------------------------------------------------------------
-- P10.2 Order ID -> order date consistency
--
-- One order should normally have one order date.
-- ---------------------------------------------------------------------------

SELECT
    order_id,
    COUNT(DISTINCT order_date) AS distinct_order_dates,
    STRING_AGG(
        DISTINCT order_date,
        ' | '
        ORDER BY order_date
    ) AS order_dates
FROM staging.orders
WHERE order_id IS NOT NULL
GROUP BY order_id
HAVING COUNT(DISTINCT order_date) > 1
ORDER BY distinct_order_dates DESC;


-- ---------------------------------------------------------------------------
-- P10.3 Product ID -> sub-category/category consistency
--
-- Check whether a product jumps between categories.
-- ---------------------------------------------------------------------------

SELECT
    product_id,
    COUNT(DISTINCT category) AS categories,
    COUNT(DISTINCT sub_category) AS sub_categories
FROM staging.orders
WHERE product_id IS NOT NULL
GROUP BY product_id
HAVING COUNT(DISTINCT category) > 1
    OR COUNT(DISTINCT sub_category) > 1
ORDER BY product_id;


-- ---------------------------------------------------------------------------
-- P10.4 Postal code shape
--
-- Postal code is TEXT because leading zeroes matter.
-- Check whether non-null values are five numeric digits.
-- ---------------------------------------------------------------------------

SELECT
    COUNT(*) AS invalid_postal_codes
FROM staging.orders
WHERE postal_code IS NOT NULL
  AND trim(postal_code) <> ''
  AND postal_code !~ '^[0-9]{5}$';


-- Inspect invalid postal codes
SELECT
    postal_code,
    COUNT(*) AS occurrences
FROM staging.orders
WHERE postal_code IS NOT NULL
  AND trim(postal_code) <> ''
  AND postal_code !~ '^[0-9]{5}$'
GROUP BY postal_code
ORDER BY occurrences DESC, postal_code;


-- ---------------------------------------------------------------------------
-- P10.5 Row ID uniqueness
-- ---------------------------------------------------------------------------

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT row_id) AS distinct_row_ids,
    COUNT(*) - COUNT(DISTINCT row_id) AS duplicate_row_id_gap
FROM staging.orders;


-- ---------------------------------------------------------------------------
-- P10.6 Customer ID -> segment consistency
--
-- A customer appearing in multiple segments may indicate bad source data.
-- ---------------------------------------------------------------------------

SELECT
    customer_id,
    COUNT(DISTINCT segment) AS distinct_segments,
    STRING_AGG(
        DISTINCT segment,
        ' | '
        ORDER BY segment
    ) AS segments
FROM staging.orders
WHERE customer_id IS NOT NULL
GROUP BY customer_id
HAVING COUNT(DISTINCT segment) > 1
ORDER BY distinct_segments DESC;


-- ---------------------------------------------------------------------------
-- P10.7 Negative profit
--
-- Negative profit may be legitimate, so this is an observation rather
-- than automatically a defect.
-- ---------------------------------------------------------------------------

SELECT
    COUNT(*) AS negative_profit_rows
FROM staging.orders
WHERE profit ~ '^-?[0-9]+(\.[0-9]+)?$'
  AND profit::numeric < 0;


-- ---------------------------------------------------------------------------
-- P10.8 Suspicious whitespace in identifiers
-- ---------------------------------------------------------------------------

SELECT
    'order_id' AS column_name,
    COUNT(*) AS whitespace_variants
FROM staging.orders
WHERE order_id IS NOT NULL
  AND order_id <> trim(order_id)

UNION ALL

SELECT
    'customer_id',
    COUNT(*)
FROM staging.orders
WHERE customer_id IS NOT NULL
  AND customer_id <> trim(customer_id)

UNION ALL

SELECT
    'product_id',
    COUNT(*)
FROM staging.orders
WHERE product_id IS NOT NULL
  AND product_id <> trim(product_id);


-- ---------------------------------------------------------------------------
-- P10.9 Suspicious blank-like values
--
-- NULL and '' are not the only ways bad source data represents "missing".
-- Look for common placeholders.
-- ---------------------------------------------------------------------------

SELECT
    'customer_name' AS column_name,
    customer_name AS suspicious_value,
    COUNT(*) AS occurrences
FROM staging.orders
WHERE lower(trim(customer_name)) IN (
    'n/a',
    'na',
    'null',
    'none',
    'unknown',
    '-'
)
GROUP BY customer_name

UNION ALL

SELECT
    'product_name',
    product_name,
    COUNT(*)
FROM staging.orders
WHERE lower(trim(product_name)) IN (
    'n/a',
    'na',
    'null',
    'none',
    'unknown',
    '-'
)
GROUP BY product_name

ORDER BY occurrences DESC;
