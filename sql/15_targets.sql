-- =============================================================================
-- 15_targets.sql - Target vs actual  (register IDs TA-01..TA-03)
-- =============================================================================
-- The second source, and a real integration problem. The targets file was
-- maintained by three different people and it shows.
--
-- The repair itself lives in 05_dimensional_model.sql (core.region_map and
-- core.fact_target). This file does two things with it: reports target vs
-- actual, and audits whether the file is trustworthy enough to be shown to a
-- board at all - which is TA-03, and is the more senior question.
--
-- Deliberately NOT solved with a fuzzy match. An explicit crosswalk can be put
-- in front of Anand and confirmed in thirty seconds. A trigram similarity
-- score cannot be confirmed by anybody, and it silently re-maps itself the
-- day someone adds a new spelling.
-- =============================================================================

\pset pager off


-- =============================================================================
-- TA-03 (run FIRST, on purpose) - are the targets reliable enough to use?
-- approach: audit the source before reporting from it. If the answer is no,
--           TA-01 and TA-02 should not go on a board slide, and finding that
--           out after building the visual is the expensive order to do it in.
-- =============================================================================

-- What the raw file actually contains.
SELECT
    count(*)                                                     AS raw_rows,
    count(DISTINCT btrim(region))                                AS raw_region_spellings,
    count(DISTINCT (btrim(region), btrim(year)))                 AS raw_region_years,
    count(*) - count(DISTINCT (btrim(region), btrim(year)))      AS duplicate_rows,
    count(*) FILTER (WHERE NULLIF(btrim(units), '') IS NOT NULL) AS rows_with_a_units_label,
    count(*) FILTER (WHERE NULLIF(btrim(owner), '') IS NULL)     AS rows_with_no_owner
FROM staging.targets;

-- The spellings, and what each one was mapped to. This is the table you show
-- Anand.
SELECT btrim(t.region) AS raw_spelling, m.region AS mapped_to, count(*) AS rows
FROM staging.targets t
LEFT JOIN core.region_map m ON m.raw_region = btrim(t.region)
GROUP BY 1, 2
ORDER BY 2, 1;

-- Unit damage: which rows were stored in thousands, and what the repair did.
SELECT region, year, supplied_units,
       raw_target_as_supplied,
       revenue_target,
       CASE WHEN supplied_units = '000s' THEN 'multiplied by 1,000' ELSE 'unchanged' END AS treatment
FROM core.fact_target
WHERE supplied_units = '000s'
ORDER BY region, year;

-- Completeness: 4 regions x 4 years = 16 expected. Which are missing?
-- FULL OUTER JOIN, not INNER: an inner join hides exactly the rows that matter.
WITH expected AS (
    SELECT r.region, y.year
    FROM (SELECT DISTINCT region FROM core.dim_geography) r
    CROSS JOIN (SELECT DISTINCT year FROM core.dim_date) y
)
SELECT e.region, e.year,
       CASE WHEN t.region IS NULL THEN 'NO TARGET SET' ELSE 'ok' END AS status
FROM expected e
FULL OUTER JOIN core.fact_target t ON t.region = e.region AND t.year = e.year
ORDER BY e.region, e.year;

-- Plausibility: a target that is wildly out of line with the region's own
-- history is more likely to be a typo than a stretch goal. Ratio to the prior
-- year's actual is the cheapest test that catches a unit error the mapping
-- missed.
WITH actual AS (
    SELECT g.region, d.year, sum(f.sales) AS revenue
    FROM core.fact_order_line f
    JOIN core.dim_geography g ON g.geography_key = f.geography_key
    JOIN core.dim_date      d ON d.date_key      = f.date_key
    GROUP BY g.region, d.year
)
SELECT t.region, t.year,
       t.revenue_target::numeric(14,2)                              AS target,
       a.revenue::numeric(14,2)                                     AS actual_same_year,
       round(t.revenue_target / a.revenue, 2)                       AS target_to_actual_ratio,
       CASE WHEN t.revenue_target / a.revenue NOT BETWEEN 0.5 AND 2.0
            THEN 'IMPLAUSIBLE - check units' ELSE '' END            AS flag
FROM core.fact_target t
JOIN actual a ON a.region = t.region AND a.year = t.year
ORDER BY target_to_actual_ratio DESC;


-- =============================================================================
-- TA-01 - How did each region perform against its annual revenue target?
-- approach: FULL OUTER JOIN so that "actual with no target" and "target with
--           no actual" both surface instead of silently disappearing.
--           The missing Central 2018 target is NOT invented. It shows as
--           "no target set", which is itself a finding: nobody noticed for
--           four years that a region-year had no number against it.
-- =============================================================================

WITH actual AS (
    SELECT g.region, d.year, sum(f.sales) AS revenue
    FROM core.fact_order_line f
    JOIN core.dim_geography g ON g.geography_key = f.geography_key
    JOIN core.dim_date      d ON d.date_key      = f.date_key
    GROUP BY g.region, d.year
)
SELECT
    coalesce(a.region, t.region)                                     AS region,
    coalesce(a.year, t.year)                                         AS year,
    t.revenue_target::numeric(14,2)                                  AS target,
    a.revenue::numeric(14,2)                                         AS actual,
    (a.revenue - t.revenue_target)::numeric(14,2)                    AS variance,
    round(100.0 * a.revenue / nullif(t.revenue_target, 0), 1)        AS attainment_pct,
    CASE WHEN t.revenue_target IS NULL THEN 'NO TARGET SET'
         WHEN a.revenue       IS NULL THEN 'TARGET WITH NO ACTUAL'
         WHEN a.revenue >= t.revenue_target THEN 'met'
         ELSE 'missed' END                                           AS status
FROM actual a
FULL OUTER JOIN core.fact_target t ON t.region = a.region AND t.year = a.year
ORDER BY region, year;


-- =============================================================================
-- TA-02 - Which regions are materially above or below target?
-- approach: attainment by region across the years that have a target, with the
--           number of comparable years stated so nobody compares a 4-year
--           record against a 3-year one without noticing.
-- =============================================================================

WITH actual AS (
    SELECT g.region, d.year, sum(f.sales) AS revenue
    FROM core.fact_order_line f
    JOIN core.dim_geography g ON g.geography_key = f.geography_key
    JOIN core.dim_date      d ON d.date_key      = f.date_key
    GROUP BY g.region, d.year
),
joined AS (
    SELECT t.region, t.year, t.revenue_target, a.revenue
    FROM core.fact_target t
    JOIN actual a ON a.region = t.region AND a.year = t.year
)
SELECT
    region,
    count(*)                                                       AS years_with_a_target,
    count(*) FILTER (WHERE revenue >= revenue_target)              AS years_met,
    sum(revenue_target)::numeric(14,2)                             AS total_target,
    sum(revenue)::numeric(14,2)                                    AS total_actual,
    round(100.0 * sum(revenue) / sum(revenue_target), 1)           AS attainment_pct,
    round(100.0 * max(revenue) FILTER (WHERE year = 2021)
              / max(revenue_target) FILTER (WHERE year = 2021), 1) AS attainment_2021_pct
FROM joined
GROUP BY region
ORDER BY attainment_pct DESC;

-- The number Anand actually asked for: 2021 target vs actual, by region.
WITH actual AS (
    SELECT g.region, sum(f.sales) AS revenue
    FROM core.fact_order_line f
    JOIN core.dim_geography g ON g.geography_key = f.geography_key
    JOIN core.dim_date      d ON d.date_key      = f.date_key
    WHERE d.year = 2021
    GROUP BY g.region
)
SELECT a.region,
       t.revenue_target::numeric(14,2)                       AS target_2021,
       a.revenue::numeric(14,2)                              AS actual_2021,
       (a.revenue - t.revenue_target)::numeric(14,2)         AS variance,
       round(100.0 * a.revenue / t.revenue_target, 1)        AS attainment_pct
FROM actual a
LEFT JOIN core.fact_target t ON t.region = a.region AND t.year = 2021
ORDER BY attainment_pct DESC;
