# Hints

Three tiers per task:

- **Hint 1 — nudge.** Names the concept. Try this first.
- **Hint 2 — method.** The approach plus the code *shape*. No answer.
- **Hint 3 — near-solution.** Working code with the project-specific bits blanked.

**The 20-minute rule.** Stuck 20 min → Hint 1. Another 15 → Hint 2. Another 15 → Hint 3.
Using hints is not failure. Opening Hint 3 first is, because the struggle is what makes it stick.

After using any hint, add one line to `analysis/learning-log.md`. That file becomes your revision
notes and your honest answer to *"what was hard about this project?"*

Concepts referenced as **P§n** live in [`../_shared/ANALYST-PRIMER.md`](../_shared/ANALYST-PRIMER.md).

---

# Day 0

## D0.1 — Turning the brief into questions

<details><summary><b>Hint 1 — nudge</b></summary>

Read the brief three times with a different job each time:

1. **Literal pass** — highlight every sentence containing a question mark or the words *which*,
   *what*, *how*, *whether*.
2. **Implied pass** — find the asks phrased as complaints or worries. "Returns are eating us
   alive" is a question. "West has been loud about being under-resourced" is a question.
3. **Structural pass** — what does she need that she did *not* ask for, because she assumes it?
   She wants target vs actual, so you need a target source. She wants "prove it", so you need
   validation. She wants decisions, so you need at least one costed recommendation.

Both forwarded messages contain asks. One of them introduces a whole second data source.
</details>

<details><summary><b>Hint 2 — method</b></summary>

Work group by group. For each, ask the same four questions and you will generate 4-6 rows:

| Probe | Produces |
|---|---|
| What is the **total**? | A KPI question |
| How does it **change over time**? | A trend question |
| How does it **split** by category / region / segment? | A breakdown question |
| Which members are **outliers**, high and low? | A ranked question |
| *(then)* What should we **do** about the worst one? | A decision question |

Groups to use: `SP` sales, `PP` product, `CA` customer, `RP` regional, `RT` returns. The sixth
group is the one Anand's forward introduces — targets versus actuals. Give it its own prefix
(`TG` works).

Sharpen each until it has a **subject, metric, comparison and period**. "Analyse returns" is not
a question. "What % of gross revenue is lost to returns, by category, in FY2021 vs FY2020?" is.
</details>

<details><summary><b>Hint 3 — near-solution</b></summary>

Here are six rows to show the shape and the level of sharpness expected. Write the other ~20
yourself, then compare with `_SEALED-question-list.md`.

| ID | Question | Type |
|---|---|---|
| SP2 | How have monthly revenue and profit moved YoY, and which months and categories drove the gap between revenue growth and profit growth? | X |
| PP6 | At what discount rate does contribution margin cross zero, by sub-category? | X |
| PP7 | What did discounting beyond that break-even cost us in FY2021, in rupees? | ! |
| RP3 | Which regions grew revenue fastest, and what happened to their margin over the same period? | X |
| TG1 | By region and year, actual revenue vs target — who missed, by how much, and is the miss widening? | D |
| RT5 | Are our highest-return sub-categories also our top sellers, and what is the net contribution after returns? | X |

Note `PP6` → `PP7`: a diagnostic question feeding a decision question. Aim for at least four
pairs like that. Types: `D` descriptive, `X` diagnostic, `!` decision (**P§3.5**).
</details>

---

# Day 1 — ingest, prove, model

## D1.1 — Loading everything as text

<details><summary><b>Hint 1 — nudge</b></summary>

Every column in `staging` is `text`. That feels wrong to an engineer — you want types. Resist it.

The reason: if you declare `Sales numeric` and one row contains `1,234.56`, the whole load fails
and you learn nothing about *how many* rows are bad. Load as text, profile, *then* cast. The
failure becomes data instead of an error.

`\copy` (psql client-side) not `COPY` (server-side) — the Postgres service account cannot read
your Documents folder.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
CREATE TABLE staging.orders (
    row_id text, order_id text, order_date text, ship_date text,
    ...   -- all 21, all text, names snake_cased from the CSV header
);
```
Then from **psql** (not pgAdmin — it cannot run `\copy`):
```
\copy staging.orders FROM '<path>/orders.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
```
`\copy` maps columns **by position, not by name**. Your `CREATE TABLE` column order must match
the CSV header order exactly.

Run the file with `ON_ERROR_STOP=1` so a half-applied script fails loudly:
```
psql -h 127.0.0.1 -U postgres -d ecommerce -v ON_ERROR_STOP=1 -f sql/01_staging_load.sql
```
</details>

<details><summary><b>Hint 3 — near-solution</b></summary>

```sql
-- Check immediately after loading. If these do not match the files, stop.
SELECT 'orders'  AS file, count(*) AS rows FROM staging.orders
UNION ALL SELECT 'returns', count(*) FROM staging.returns
UNION ALL SELECT 'targets', count(*) FROM staging.targets;
```
Compare against the shell:
```
wc -l "<path>/orders.csv"      # expect rows + 1 for the header
```
Expect roughly 1,000,000 order lines. Exact count varies — the builder injects a random number of
defect rows, and duplicate-row defects *add* rows. A mismatch of a few thousand is not
automatically wrong; a mismatch of hundreds of thousands is.
</details>

## D1.2 — Proving the grain

<details><summary><b>Hint 1 — nudge</b></summary>

**P§3.1.** Grain = what one row represents. You must write it as a sentence *and* prove it with
a query. Your candidate: "one row = one product line on one order."

Prove it by testing whether `(order_id, product_id)` is unique. If it is not, your grain sentence
is wrong — and you need to find out what the real grain is before modelling anything.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
SELECT count(*)                                        AS rows,
       count(DISTINCT (order_id, product_id))          AS distinct_pairs,
       count(*) - count(DISTINCT (order_id, product_id)) AS excess
FROM   staging.orders;
```
If `excess > 0`, look at the offenders before deciding anything:
```sql
SELECT order_id, product_id, count(*)
FROM   staging.orders GROUP BY 1,2 HAVING count(*) > 1
ORDER  BY 3 DESC LIMIT 20;
```
Then ask: are these **genuine duplicates** (every column identical — a data defect) or the **same
product legitimately on one order twice** at different discounts (real, and your grain sentence
needs to include a line number)? The answer changes your model. Check by comparing all columns
for a couple of offending pairs.
</details>

<details><summary><b>Hint 3 — near-solution</b></summary>

```sql
-- Distinguish exact duplicates from legitimate repeats
WITH d AS (
    SELECT order_id, product_id, count(*) AS n,
           count(DISTINCT (sales, quantity, discount, profit)) AS distinct_values
    FROM   staging.orders
    GROUP  BY 1, 2 HAVING count(*) > 1
)
SELECT CASE WHEN distinct_values = 1 THEN 'exact duplicate'
            ELSE 'same product, different line values' END AS kind,
       count(*) AS pairs, sum(n) AS rows
FROM   d GROUP BY 1;
```
Write the verdict into `analysis/data-quality-log.md` under **Grain statement** as a sentence,
e.g. *"One row of `fact_order_line` represents one product line on one order; `(order_id,
product_id)` is unique after removing N exact duplicates."*
</details>

## D1.3 — Finding the defects (you have NOT been told what they are)

<details><summary><b>Hint 1 — nudge</b></summary>

You are looking for unknown unknowns. The method is to interrogate every column the same way
rather than guess what is wrong.

For each column ask: how many nulls / blanks? How many distinct values, and does that number make
sense? What are the min and max? For text — are there values that differ only by case or
whitespace? For numbers — are any outside a physically possible range? For dates — are any out of
window, or is any pair in the wrong order?

Seven defects were injected from a menu of sixteen, at rates between 0.04% and 0.6%. At 1M rows
that is 400 to 6,000 rows each — invisible unless you count deliberately.
</details>

<details><summary><b>Hint 2 — method</b></summary>

Profile all 21 columns at once instead of writing 21 queries. Unpivot with `to_jsonb`:

```sql
SELECT key AS column_name,
       count(*)                                            AS rows,
       count(*) FILTER (WHERE value IS NULL OR value = '') AS blanks,
       count(DISTINCT value)                               AS distinct_values,
       min(value)                                          AS min_value,
       max(value)                                          AS max_value
FROM   staging.orders o,
       LATERAL jsonb_each_text(to_jsonb(o))
GROUP  BY key ORDER BY key;
```

Then targeted checks. The high-yield family is **"values that should be identical but are not"**:
```sql
SELECT region, count(*) FROM staging.orders GROUP BY 1 ORDER BY 2 DESC;
-- if you see 'West', 'west' and ' West ' as three rows, you have found two defects
```
Compare `trim(lower(x))` distinct count against raw distinct count for every text column. Any gap
is a defect.

Also worth running: `octet_length(x) <> length(x)` finds non-ASCII characters hiding in text.
</details>

<details><summary><b>Hint 3 — near-solution</b></summary>

A defect sweep that covers most of the menu. Run it, then investigate every non-zero row.

```sql
WITH checks AS (
  SELECT 'blank postal code'      AS check, count(*) FROM staging.orders WHERE postal_code IS NULL OR postal_code = ''
  UNION ALL SELECT 'ship before order',     count(*) FROM staging.orders WHERE ship_date < order_date
  UNION ALL SELECT 'negative quantity',     count(*) FROM staging.orders WHERE quantity ~ '^-'
  UNION ALL SELECT 'discount out of range', count(*) FROM staging.orders WHERE discount::numeric < 0 OR discount::numeric > 1
  UNION ALL SELECT 'zero sales, qty > 0',   count(*) FROM staging.orders WHERE sales::numeric = 0 AND quantity::numeric > 0
  UNION ALL SELECT 'sales not numeric',     count(*) FROM staging.orders WHERE sales !~ '^-?[0-9]+\.?[0-9]*$'
  UNION ALL SELECT 'date not ISO',          count(*) FROM staging.orders WHERE order_date !~ '^\d{4}-\d{2}-\d{2}$'
  UNION ALL SELECT 'order date out of window', count(*) FROM staging.orders
                                            WHERE order_date ~ '^\d{4}-\d{2}-\d{2}$'
                                              AND (order_date::date < '2018-01-01' OR order_date::date > '2021-12-31')
  UNION ALL SELECT 'region needs trim/case', count(*) FROM staging.orders WHERE region <> trim(region) OR region <> initcap(trim(region))
  UNION ALL SELECT 'category needs trim',    count(*) FROM staging.orders WHERE category <> trim(category)
  UNION ALL SELECT 'ship_mode needs trim',   count(*) FROM staging.orders WHERE ship_mode <> trim(ship_mode)
  UNION ALL SELECT 'duplicate row_id',       count(*) FROM (SELECT row_id FROM staging.orders GROUP BY 1 HAVING count(*) > 1) x
  UNION ALL SELECT 'product_id, 2+ names',   count(*) FROM (SELECT product_id FROM staging.orders GROUP BY 1 HAVING count(DISTINCT product_name) > 1) x
  UNION ALL SELECT 'customer_id, 2+ names',  count(*) FROM (SELECT customer_id FROM staging.orders GROUP BY 1 HAVING count(DISTINCT customer_name) > 1) x
)
SELECT * FROM checks WHERE count > 0 ORDER BY count DESC;
```

> Careful: `discount::numeric` throws if any value is non-numeric. If it errors, that is itself a
> finding — wrap with a regex guard or use a `CASE`. Casting inside a profiling query is where
> beginners get stuck; the fix is to test the *shape* with a regex before casting.

Every non-zero row becomes a row in the DQ log with a decision. Not all defects get the same
treatment — see D1.4.
</details>

## D1.4 — Cleaning, and what to do with each defect

<details><summary><b>Hint 1 — nudge</b></summary>

Three possible treatments, and choosing between them is the actual analyst work:

- **Fix** — the true value is recoverable. `' West '` → `'West'`. Trailing spaces, case, thousands
  separators, date format drift. No information is lost, so just fix it and log it.
- **Quarantine** — the row is unusable but you must not pretend it never existed. Negative
  quantity, sales = 0 with quantity > 0, discount > 1. Move to `core.rejected` with a reason.
- **Keep and flag** — it looks wrong but is real. **Negative profit is not an error.** It is half
  your analysis. Never filter it.

**Quarantine, never delete** (**P§6**). `clean + rejected = staged` is a check you can run; a
`WHERE` clause is not.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
CREATE TABLE core.rejected (LIKE staging.orders, reject_reason text, rejected_at timestamptz DEFAULT now());

WITH classified AS (
    SELECT *,
           CASE WHEN quantity::numeric <= 0                  THEN 'non-positive quantity'
                WHEN discount::numeric < 0
                  OR discount::numeric > 1                   THEN 'discount out of range'
                WHEN sales::numeric = 0
                 AND quantity::numeric > 0                   THEN 'zero sales with quantity'
                ELSE NULL END AS reject_reason
    FROM staging.orders
)
INSERT INTO core.rejected SELECT * FROM classified WHERE reject_reason IS NOT NULL;
-- then INSERT the reject_reason IS NULL rows into core.orders_clean, casting as you go
```

Casting rules that matter:
- **Money → `numeric`, never `float`.** `float` gives you `1234.5600000000001` at the gate.
- Strip thousands separators before casting: `replace(sales, ',', '')::numeric`.
- Handle both date formats: `CASE WHEN order_date ~ '^\d{4}' THEN order_date::date ELSE to_date(order_date,'DD-MM-YYYY') END`.
- Empty string is not NULL: `NULLIF(postal_code, '')`.
- Normalise text once: `initcap(trim(region))`.
</details>

<details><summary><b>Hint 3 — near-solution</b></summary>

The check that must pass before you move on:

```sql
SELECT (SELECT count(*) FROM core.orders_clean) AS clean,
       (SELECT count(*) FROM core.rejected)     AS rejected,
       (SELECT count(*) FROM staging.orders)    AS staged,
       (SELECT count(*) FROM core.orders_clean)
     + (SELECT count(*) FROM core.rejected)
     - (SELECT count(*) FROM staging.orders)    AS difference;
```
`difference` must be exactly `0`. If it is not, you have a `WHERE` clause somewhere that drops
rows into neither bucket — find it now, not on Day 4.

Your DQ log row should read like:

| # | Issue found | Where | Decision | Rows | Why |
|---|---|---|---|---|---|
| 3 | `region` in mixed case and with padding | `staging.orders` | Normalised with `initcap(trim())` | 2,300 | Grouping split 'West' across three phantom categories; no information lost by normalising |
| 4 | `quantity` negative | `staging.orders` | Quarantined, reason `non-positive quantity` | 3,826 | Cannot be a real order line; keeping them would understate volume and corrupt AOV |
</details>

## D1.5 — The star schema

<details><summary><b>Hint 1 — nudge</b></summary>

**P§2.** Seven tables: `dim_date`, `dim_customer`, `dim_product`, `dim_geography`,
`fact_order_line`, `fact_return`, `fact_target`.

The dimension rule: **exactly one row per business entity.** If `product_id` maps to two names,
you must pick one before that table can exist. There is no correct answer — most recent, most
frequent, longest — but there *is* a requirement to decide, log it, and be consistent.

The fact rule: `fact_order_line` keeps `order_id` even though there is no order dimension. That
is a **degenerate dimension** (**P§7**) and it is how `fact_return` relates.
</details>

<details><summary><b>Hint 2 — method</b></summary>

Deduplicate a dimension with `DISTINCT ON` (Postgres-specific and very handy):

```sql
CREATE TABLE core.dim_product AS
SELECT DISTINCT ON (product_id)
       product_id, product_name, category, sub_category
FROM   core.orders_clean
ORDER  BY product_id, order_date DESC;     -- keeps the most recent name per product
```

`fact_return` **must be at order grain** — one row per returned order, no more:
```sql
CREATE TABLE core.fact_return AS
SELECT DISTINCT order_id FROM core.returns_clean;   -- DISTINCT is doing the real work
```
The returns file contains duplicated rows on purpose. Without `DISTINCT` you fan out (**P§3.1**).

Add PKs and FKs **after** loading — a failing FK then is one clear error pointing at a real data
problem, rather than a slow insert.
</details>

<details><summary><b>Hint 3 — near-solution</b></summary>

```sql
-- Surrogate keys vs natural keys: natural keys here (customer_id, product_id) are stable text
-- and defensible at this size. Pick one approach, write down why in the README, be consistent.

ALTER TABLE core.dim_product    ADD PRIMARY KEY (product_id);
ALTER TABLE core.dim_customer   ADD PRIMARY KEY (customer_id);
ALTER TABLE core.dim_date       ADD PRIMARY KEY (date_key);
ALTER TABLE core.dim_geography  ADD PRIMARY KEY (geo_key);
ALTER TABLE core.fact_return    ADD PRIMARY KEY (order_id);

ALTER TABLE core.fact_order_line
  ADD FOREIGN KEY (product_id)  REFERENCES core.dim_product(product_id),
  ADD FOREIGN KEY (customer_id) REFERENCES core.dim_customer(customer_id),
  ADD FOREIGN KEY (order_date)  REFERENCES core.dim_date(date_key),
  ADD FOREIGN KEY (geo_key)     REFERENCES core.dim_geography(geo_key);

-- orphan check: must all return 0
SELECT count(*) FROM core.fact_order_line f
LEFT JOIN core.dim_product p USING (product_id) WHERE p.product_id IS NULL;
```

**`dim_geography` grain is a real decision.** One row per postal code, or per city+state? Blank
postal codes force the issue. Whichever you choose, `geo_key` must be unique and every fact row
must resolve to exactly one. A common answer: `md5(state || city || coalesce(postal_code,''))`.
</details>

## D1.6 — `dim_date`

<details><summary><b>Hint 1 — nudge</b></summary>

Build it from `generate_series`, **never** from the dates present in the fact table. A date table
built from facts has a hole on every day with no orders, and time intelligence silently
mis-computes across the gaps (**P§8.6**).
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
CREATE TABLE core.dim_date AS
SELECT d::date                             AS date_key,
       extract(year    FROM d)::int        AS year,
       extract(quarter FROM d)::int        AS quarter,
       extract(month   FROM d)::int        AS month_no,
       to_char(d, 'Mon')                   AS month_name,
       to_char(d, 'YYYY-MM')               AS year_month,
       extract(isodow  FROM d)::int        AS day_of_week,
       (extract(isodow FROM d) >= 6)       AS is_weekend
FROM generate_series('2018-01-01'::date, '2021-12-31'::date, '1 day') AS d;
```
1,461 rows. Add `month_name_sort` (the month number) — Power BI needs a numeric column to sort
`Jan, Feb, Mar` correctly instead of alphabetically (`Apr, Aug, Dec...`). This catches everyone once.
</details>

## D1.7 — Indexes and `EXPLAIN`

<details><summary><b>Hint 1 — nudge</b></summary>

At 1M rows a missing index stops being theoretical. Find your slowest analytical query, run
`EXPLAIN ANALYZE` on it, add the index the plan implies, run it again, and **record both timings**
— that before/after pair is a portfolio artefact and an interview answer.

Look for `Seq Scan` on `fact_order_line` inside a query that filters or joins on a small subset.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('month', order_date) AS m, sum(sales)
FROM core.fact_order_line
WHERE order_date >= '2021-01-01'
GROUP BY 1;
```
Read the top line's `actual time=...` and the node types. Then:
```sql
CREATE INDEX idx_fol_order_date ON core.fact_order_line (order_date);
CREATE INDEX idx_fol_product    ON core.fact_order_line (product_id);
CREATE INDEX idx_fol_customer   ON core.fact_order_line (customer_id);
-- composite for the common "one dimension, over time" shape
CREATE INDEX idx_fol_prod_date  ON core.fact_order_line (product_id, order_date);
ANALYZE core.fact_order_line;
```
Re-run the `EXPLAIN`. Record both numbers in `analysis/query-tuning.md`.

Do not index everything. Each index costs write time and space; the point is to demonstrate you
can identify *which* one a plan is asking for.
</details>

## D1.8 — The reconciliation gate

<details><summary><b>Hint 1 — nudge</b></summary>

**One query returning one row per metric with a verdict column.** Not five queries you eyeball.
A gate you have to squint at is a gate you wave through at hour seven when you are tired.

Metrics to tie: row count, `sum(sales)`, `sum(profit)`, `sum(quantity)`, distinct orders,
distinct customers. Plus a sanity check on the return rate.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
WITH stg AS (
    SELECT count(*)                                       AS rows,
           sum(replace(sales,',','')::numeric)            AS sales,
           sum(profit::numeric)                           AS profit
    FROM staging.orders
    WHERE <the same rows you did NOT reject>
), cor AS (
    SELECT count(*) AS rows, sum(sales) AS sales, sum(profit) AS profit
    FROM core.fact_order_line
)
SELECT 'rows'   AS metric, stg.rows::numeric, cor.rows::numeric,
       cor.rows - stg.rows AS diff,
       CASE WHEN cor.rows = stg.rows THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM stg, cor
UNION ALL
SELECT 'sales', stg.sales, cor.sales, cor.sales - stg.sales,
       CASE WHEN abs(cor.sales - stg.sales) < 0.01 THEN 'PASS' ELSE 'FAIL' END
FROM stg, cor
UNION ALL ...;
```

The `WHERE <the same rows you did NOT reject>` is the fiddly part and the reason the rejects table
must carry a reason: you can reconstruct exactly which rows should have made it through.
</details>

<details><summary><b>Hint 3 — near-solution</b></summary>

Simpler and stronger — reconcile against `clean + rejected` instead of re-deriving the filter:

```sql
WITH expected AS (
    SELECT count(*) AS rows, sum(sales) AS sales, sum(profit) AS profit
    FROM core.orders_clean                       -- post-cast, pre-model
), actual AS (
    SELECT count(*) AS rows, sum(sales) AS sales, sum(profit) AS profit
    FROM core.fact_order_line                    -- post-model
)
SELECT m.metric, e.v AS expected, a.v AS actual, a.v - e.v AS diff,
       CASE WHEN abs(a.v - e.v) < 0.01 THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM (VALUES ('rows'),('sales'),('profit')) m(metric)
CROSS JOIN LATERAL (SELECT CASE m.metric WHEN 'rows' THEN rows::numeric
                                         WHEN 'sales' THEN sales ELSE profit END AS v FROM expected) e
CROSS JOIN LATERAL (SELECT CASE m.metric WHEN 'rows' THEN rows::numeric
                                         WHEN 'sales' THEN sales ELSE profit END AS v FROM actual) a;
```

Then the return-rate sanity check, which is really a fan-out detector:
```sql
SELECT count(DISTINCT r.order_id)::numeric / count(DISTINCT f.order_id) AS return_rate
FROM core.fact_order_line f LEFT JOIN core.fact_return r USING (order_id);
```
Expect roughly **8%**. If you get 20-40%, you fanned out the returns join (**P§3.1**) — that is
exactly the mistake that embarrassed the last analyst in Priya's email.
</details>

---

# Day 2 — the analysis

## D2.1 — YoY, MoM and moving averages

<details><summary><b>Hint 1 — nudge</b></summary>

Window functions (**P§4.3**). Aggregate to month first in a CTE, then `LAG` over that. Do not try
to do both in one pass.

For YoY on monthly data, `LAG(x, 12)` — offset by twelve rows, which only works if every month is
present. Your `dim_date` guarantees that; joining to it rather than to the fact table directly is
what makes the offset safe.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
WITH monthly AS (
    SELECT d.year_month,
           sum(f.sales)  AS revenue,
           sum(f.profit) AS profit
    FROM   core.dim_date d
    LEFT   JOIN core.fact_order_line f ON f.order_date = d.date_key   -- LEFT keeps empty months
    GROUP  BY d.year_month
)
SELECT year_month, revenue, profit,
       lag(revenue, 1)  OVER (ORDER BY year_month)                          AS prev_month,
       lag(revenue, 12) OVER (ORDER BY year_month)                          AS same_month_ly,
       revenue / NULLIF(lag(revenue, 12) OVER (ORDER BY year_month), 0) - 1 AS yoy_pct,
       avg(revenue) OVER (ORDER BY year_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS ma3
FROM monthly ORDER BY year_month;
```
Always `NULLIF(x, 0)` on the denominator. Always.
</details>

## D2.2 — Average order value

<details><summary><b>Hint 1 — nudge</b></summary>

**P§4.2 and P§8.3.** Your fact table is at *line* grain. AOV is per **order**. `avg(sales)` gives
you average *line* value — a different, smaller, wrong number. Collapse to order grain first.
This is the single most common mistake on this dataset.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
WITH order_totals AS (
    SELECT order_id, sum(sales) AS order_value
    FROM   core.fact_order_line
    GROUP  BY order_id
)
SELECT count(*)                AS orders,
       sum(order_value)        AS revenue,
       avg(order_value)        AS aov,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY order_value) AS median_order
FROM order_totals;
```
Report the **median** alongside the mean. Order values are right-skewed, so the mean sits above
most orders. Being able to say "AOV is X but the median order is Y, so the mean is pulled by a
long tail" is a genuinely analyst-sounding observation.
</details>

## D2.3 — Seasonality

<details><summary><b>Hint 1 — nudge</b></summary>

**P§8.9.** Ranking all 48 months just finds your biggest year — and revenue grows every year here,
so you would conclude "2021 is seasonal", which is nonsense.

Seasonality means: for each calendar month, average across all years, then index against the
overall monthly average.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
WITH monthly AS (
    SELECT d.year, d.month_no, d.month_name, sum(f.sales) AS revenue
    FROM   core.dim_date d
    LEFT   JOIN core.fact_order_line f ON f.order_date = d.date_key
    GROUP  BY 1, 2, 3
), by_month AS (
    SELECT month_no, month_name, avg(revenue) AS avg_revenue
    FROM   monthly GROUP BY 1, 2
)
SELECT month_no, month_name, avg_revenue,
       avg_revenue / avg(avg_revenue) OVER () AS seasonal_index
FROM by_month ORDER BY month_no;
```
`avg(...) OVER ()` with an empty window = the grand average across all rows. An index of 1.20
means "that month runs 20% above a typical month."
</details>

## D2.4 — Pareto (what % of revenue comes from the top N%)

<details><summary><b>Hint 1 — nudge</b></summary>

Cumulative sum over a ranked list, divided by the grand total. Two window functions in one pass:
one ordered running total, one unordered grand total.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
WITH prod AS (
    SELECT p.product_id, p.product_name, sum(f.sales) AS revenue
    FROM   core.fact_order_line f
    JOIN   core.dim_product p USING (product_id)
    GROUP  BY 1, 2
)
SELECT product_name, revenue,
       row_number() OVER (ORDER BY revenue DESC)                          AS rank,
       sum(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING) AS cumulative,
       sum(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING)
         / sum(revenue) OVER ()                                           AS cum_pct,
       row_number() OVER (ORDER BY revenue DESC)::numeric
         / count(*)  OVER ()                                              AS product_pct
FROM prod ORDER BY revenue DESC;
```
The headline: find the first row where `cum_pct >= 0.80` and report its `product_pct`. That is
your "X% of products drive 80% of revenue" number.
</details>

## D2.5 — High sales, low profit

<details><summary><b>Hint 1 — nudge</b></summary>

Define "high" and "low" **from the data**, not from a number you invented. Quartiles or the
median. A threshold you picked is indefensible when someone asks "why 5 lakh?"

And pull in average discount alongside — discount is usually the mechanism, and this question is
really the setup for the margin-cliff analysis.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
WITH sub AS (
    SELECT sub_category,
           sum(sales)  AS revenue,
           sum(profit) AS profit,
           sum(profit) / NULLIF(sum(sales), 0) AS margin,
           avg(discount) AS avg_discount
    FROM   core.fact_order_line f JOIN core.dim_product p USING (product_id)
    GROUP  BY 1
), thresholds AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY revenue) AS med_rev,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY margin)  AS med_margin
    FROM sub
)
SELECT s.*,
       CASE WHEN revenue >= med_rev AND margin <  med_margin THEN 'high sales, low margin'
            WHEN revenue >= med_rev AND margin >= med_margin THEN 'star'
            WHEN revenue <  med_rev AND margin >= med_margin THEN 'niche, healthy'
            ELSE 'low sales, low margin' END AS quadrant
FROM sub s CROSS JOIN thresholds ORDER BY margin;
```
The `'high sales, low margin'` quadrant is your headline finding and becomes the scatter on P2.
</details>

## D2.6 — Consistently underperforming (not just "worst")

<details><summary><b>Hint 1 — nudge</b></summary>

**P§8.10.** "Consistent" is a **count of periods below threshold**, not an average. An average
hides a product that is fine for 10 months and catastrophic for 2 — and those two are very
different business problems with different fixes.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
WITH monthly AS (
    SELECT p.sub_category, d.year_month,
           sum(f.profit) / NULLIF(sum(f.sales), 0) AS margin
    FROM   core.fact_order_line f
    JOIN   core.dim_product p USING (product_id)
    JOIN   core.dim_date    d ON d.date_key = f.order_date
    GROUP  BY 1, 2
)
SELECT sub_category,
       count(*)                                     AS months,
       count(*) FILTER (WHERE margin < 0)           AS months_negative,
       round(100.0 * count(*) FILTER (WHERE margin < 0) / count(*), 1) AS pct_negative,
       min(margin), avg(margin)
FROM monthly GROUP BY 1
HAVING count(*) FILTER (WHERE margin < 0) >= 6      -- your definition of "consistent"
ORDER BY pct_negative DESC;
```
State your threshold explicitly in the write-up: *"consistent = negative margin in at least 6 of
48 months."* A defined threshold you can defend beats a clever one you cannot.
</details>

## D2.7 — The margin cliff (Finance's question)

<details><summary><b>Hint 1 — nudge</b></summary>

This is the most valuable query in the project — it is the one that becomes a decision.

The question: **at what discount rate does contribution margin cross zero, per sub-category?**
Band the discount, compute margin per band per sub-category, find where the sign flips.

Do not fit a regression. A band table is more convincing to a business audience and easier to
defend, and you can put it straight on a page.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
WITH banded AS (
    SELECT p.sub_category,
           width_bucket(f.discount, 0, 0.8, 16) AS band,   -- 5-point buckets
           f.sales, f.profit
    FROM   core.fact_order_line f JOIN core.dim_product p USING (product_id)
    WHERE  f.discount BETWEEN 0 AND 0.8
)
SELECT sub_category,
       (band - 1) * 0.05                             AS discount_from,
       band * 0.05                                   AS discount_to,
       count(*)                                      AS lines,
       sum(sales)                                    AS revenue,
       sum(profit)                                   AS profit,
       sum(profit) / NULLIF(sum(sales), 0)           AS margin
FROM banded GROUP BY 1, 2, 3 ORDER BY 1, 2;
```
Then find the flip point per sub-category with `LAG` over the bands — the first band where margin
goes negative while the previous was positive.
</details>

<details><summary><b>Hint 3 — near-solution</b></summary>

```sql
WITH banded AS (
    SELECT p.sub_category, width_bucket(f.discount, 0, 0.8, 16) AS band, f.sales, f.profit
    FROM core.fact_order_line f JOIN core.dim_product p USING (product_id)
    WHERE f.discount BETWEEN 0 AND 0.8
), by_band AS (
    SELECT sub_category, band, band * 0.05 AS discount_to,
           sum(profit) / NULLIF(sum(sales), 0) AS margin,
           sum(sales) AS revenue
    FROM banded GROUP BY 1, 2 HAVING count(*) >= 50      -- ignore thin bands
), flip AS (
    SELECT *, lag(margin) OVER (PARTITION BY sub_category ORDER BY band) AS prev_margin
    FROM by_band
)
SELECT sub_category,
       discount_to AS breakeven_discount_at_or_below,
       prev_margin AS margin_before, margin AS margin_after
FROM flip
WHERE margin < 0 AND prev_margin >= 0
ORDER BY discount_to;
```
`HAVING count(*) >= 50` matters — a band with 3 lines will flip on noise and give you a
break-even point you cannot defend. Say in the write-up that you required a minimum band size.

Then the cost: revenue and profit on lines sitting **above** each sub-category's break-even. That
number is the answer to Ritu's question, and Day 3 turns it into a counterfactual.
</details>

## D2.8 — RFM segmentation

<details><summary><b>Hint 1 — nudge</b></summary>

Three metrics per customer, then `NTILE(5)` on each to score 1-5, then concatenate or bucket.

- **R**ecency — days since their last order (lower is better, so invert the score)
- **F**requency — number of orders
- **M**onetary — total revenue

The inversion on recency is where everyone slips: a customer who bought yesterday should score 5,
not 1.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
WITH cust AS (
    SELECT customer_id,
           max(order_date)                                    AS last_order,
           ('2021-12-31'::date - max(order_date))             AS recency_days,
           count(DISTINCT order_id)                           AS frequency,
           sum(sales)                                         AS monetary
    FROM core.fact_order_line GROUP BY 1
), scored AS (
    SELECT *,
           ntile(5) OVER (ORDER BY recency_days DESC) AS r_score,  -- DESC inverts it
           ntile(5) OVER (ORDER BY frequency)         AS f_score,
           ntile(5) OVER (ORDER BY monetary)          AS m_score
    FROM cust
)
SELECT *, r_score::text || f_score::text || m_score::text AS rfm,
       CASE WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
            WHEN r_score >= 4 AND f_score <= 2 THEN 'New / promising'
            WHEN r_score <= 2 AND f_score >= 4 THEN 'At risk — was valuable'
            WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost'
            ELSE 'Needs attention' END AS segment
FROM scored;
```
Use a **fixed** as-of date (`2021-12-31`, your data's end) not `current_date`, or every rerun
gives different answers and nothing reproduces.
</details>

## D2.9 — Cohort retention

<details><summary><b>Hint 1 — nudge</b></summary>

The most expensive query in the sprint. Timebox it to 45 minutes and cut it if it overruns —
the fallback is a repeat-rate KPI plus a segment trend line.

Two steps: (1) find each customer's **first purchase month** — that is their cohort. (2) For every
order, compute **months since that first month**. Then count distinct customers per
(cohort, months_since) and divide by the cohort's starting size.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
WITH first_order AS (
    SELECT customer_id, date_trunc('month', min(order_date))::date AS cohort_month
    FROM core.fact_order_line GROUP BY 1
), activity AS (
    SELECT f.customer_id, fo.cohort_month,
           (extract(year  FROM age(date_trunc('month', f.order_date), fo.cohort_month)) * 12
          + extract(month FROM age(date_trunc('month', f.order_date), fo.cohort_month)))::int
             AS months_since
    FROM core.fact_order_line f JOIN first_order fo USING (customer_id)
), sizes AS (
    SELECT cohort_month, count(*) AS cohort_size FROM first_order GROUP BY 1
)
SELECT a.cohort_month, a.months_since,
       count(DISTINCT a.customer_id)                          AS active,
       s.cohort_size,
       round(100.0 * count(DISTINCT a.customer_id) / s.cohort_size, 1) AS retention_pct
FROM activity a JOIN sizes s USING (cohort_month)
WHERE a.months_since BETWEEN 0 AND 12
GROUP BY 1, 2, 4 ORDER BY 1, 2;
```
`months_since = 0` must always be 100% — that is your correctness check. If it is not, your
cohort assignment is wrong.

> Later cohorts have fewer observable months. Do not compare month-12 retention for a cohort that
> only has 3 months of history — that is survivorship bias, and noticing it is worth saying in
> the write-up.
</details>

## D2.10 — Return rate without fanning out

<details><summary><b>Hint 1 — nudge</b></summary>

`fact_return` is at **order** grain, `fact_order_line` at **line** grain (**P§3.1**). Join them
naively and every return multiplies by that order's line count.

Two safe patterns: aggregate lines to order grain first, or use `EXISTS` / `IN` instead of a join.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
-- Order-level return rate: collapse first, then join
WITH orders AS (
    SELECT order_id, sum(sales) AS order_value, sum(profit) AS order_profit
    FROM core.fact_order_line GROUP BY 1
)
SELECT count(*)                                                    AS orders,
       count(*) FILTER (WHERE r.order_id IS NOT NULL)              AS returned,
       round(100.0 * count(*) FILTER (WHERE r.order_id IS NOT NULL) / count(*), 2) AS return_rate_pct,
       sum(o.order_value) FILTER (WHERE r.order_id IS NOT NULL)    AS revenue_returned
FROM orders o LEFT JOIN core.fact_return r USING (order_id);
```
```sql
-- Return rate by category: safe because EXISTS cannot duplicate the left row
SELECT p.category,
       count(*)                                                  AS lines,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM core.fact_return r
                                      WHERE r.order_id = f.order_id)) AS returned_lines
FROM core.fact_order_line f JOIN core.dim_product p USING (product_id)
GROUP BY 1;
```
Sanity-check against the ~8% overall rate from the Day 1 gate. A category rate of 60% means you
fanned out somewhere.
</details>

## D2.11 — The targets join (the messy one)

<details><summary><b>Hint 1 — nudge</b></summary>

Open `targets.csv` in a text editor first. Actually look at it. You will find:

- the region column header has a **trailing space**
- each region is spelled several different ways
- some rows are **in thousands**, flagged only by a `Units` column
- there is a blank row, some duplicated rows, and one missing region-year

Do not try to fix this with a clever fuzzy match. Build an explicit **mapping table**. Explicit
beats clever here because you can show it to Anand and he can confirm it.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
-- 1. an explicit, auditable crosswalk
CREATE TABLE core.region_map (raw text PRIMARY KEY, region text NOT NULL);
INSERT INTO core.region_map VALUES
  ('West','West'), ('west','West'), ('West Region','West'), ('W','West'),
  ('East','East'), ('EAST','East'), ('East Region','East'), ('E','East'),
  ('Central','Central'), ('central','Central'), ('Central Region','Central'), ('C','Central'),
  ('South','South'), ('south','South'), ('South Region','South'), ('Sth','South');

-- 2. clean, normalise units, dedupe
CREATE TABLE core.fact_target AS
SELECT m.region, t.year::int AS year,
       CASE WHEN trim(t.units) = '000s' THEN t.revenue_target::numeric * 1000
            ELSE t.revenue_target::numeric END AS revenue_target
FROM (SELECT DISTINCT * FROM staging.targets
      WHERE nullif(trim(region_raw), '') IS NOT NULL) t     -- drops the blank row + exact dupes
JOIN core.region_map m ON trim(t.region_raw) = m.raw;
```
Two things to verify and log:
- **Every raw value mapped.** `LEFT JOIN` and check for NULLs. An unmapped spelling silently
  drops a whole region-year.
- **One row per region-year.** `GROUP BY region, year HAVING count(*) > 1` must return nothing.
  If a genuine duplicate has *different* values, that is a business question, not a code fix —
  log it and pick a rule.
- **The missing region-year.** One is absent. Do not invent it. Show it as "no target set" on the
  dashboard — an honest gap beats a fabricated number, and noticing it is itself a finding.
</details>

<details><summary><b>Hint 3 — near-solution</b></summary>

```sql
-- coverage check: run BEFORE trusting the join
SELECT trim(t.region_raw) AS unmapped, count(*)
FROM   staging.targets t
LEFT   JOIN core.region_map m ON trim(t.region_raw) = m.raw
WHERE  m.raw IS NULL AND nullif(trim(t.region_raw), '') IS NOT NULL
GROUP  BY 1;                              -- must return zero rows

-- target vs actual
WITH actual AS (
    SELECT g.region, d.year, sum(f.sales) AS actual_revenue
    FROM core.fact_order_line f
    JOIN core.dim_geography g USING (geo_key)
    JOIN core.dim_date d ON d.date_key = f.order_date
    GROUP BY 1, 2
)
SELECT COALESCE(a.region, t.region) AS region,
       COALESCE(a.year, t.year)     AS year,
       a.actual_revenue, t.revenue_target,
       a.actual_revenue - t.revenue_target                          AS variance,
       round(100.0 * (a.actual_revenue / NULLIF(t.revenue_target,0) - 1), 1) AS variance_pct
FROM actual a FULL OUTER JOIN core.fact_target t USING (region, year)
ORDER BY region, year;
```
`FULL OUTER JOIN` deliberately: it surfaces both "actuals with no target" (the missing row) and
"target with no actuals". An `INNER JOIN` would hide exactly the thing worth reporting.
</details>

---

# Day 3 — change request, model, DAX

## D3.1 — The counterfactual, as a range

<details><summary><b>Hint 1 — nudge</b></summary>

"What would we have earned with discounts capped at 20%?" The naive answer assumes every order
still happens at the lower discount. That is certainly false — some only converted *because* of
the discount.

You cannot observe price elasticity in this data. So do not pretend to a point estimate. Give a
**bounded range** and state which assumption drives each end. See `_SEALED-change-request.md` §3.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```sql
WITH capped AS (
    SELECT f.*, p.sub_category,
           LEAST(f.discount, 0.20)                     AS capped_discount,
           f.sales / NULLIF(1 - f.discount, 0)         AS list_value   -- undiscounted value
    FROM core.fact_order_line f JOIN core.dim_product p USING (product_id)
    WHERE f.discount > 0.20
), repriced AS (
    SELECT *,
           list_value * (1 - capped_discount)                            AS sales_at_cap,
           list_value * (1 - capped_discount) - (list_value - sales - profit) AS profit_at_cap
    FROM capped
)
SELECT count(*)                                AS affected_lines,
       sum(sales)                              AS sales_today,
       sum(profit)                             AS profit_today,
       sum(sales_at_cap)                       AS sales_upper_bound,
       sum(profit_at_cap)                      AS profit_upper_bound,
       sum(profit_at_cap) - sum(profit)        AS profit_recovered_if_all_survive,
       -sum(profit)                            AS profit_lost_if_all_churn
FROM repriced;
```
`profit_recovered_if_all_survive` is your **upper** bound. `profit_lost_if_all_churn` is the
**lower** bound (you lose the contribution those orders were making). Reality is between.

The cost line `(list_value - sales - profit)` assumes unit cost is unchanged by discount — which
is true, and worth stating, because that is what makes the recalculation valid at all.
</details>

## D3.2 — The Power BI model

<details><summary><b>Hint 1 — nudge</b></summary>

Five rules, all of them things that silently break later if skipped:

1. **Single-direction relationships**, dimension → fact. Never bidirectional "to make it work."
2. **Mark `dim_date` as a date table** (Table tools → Mark as date table). Time intelligence
   returns wrong answers without it, with no warning.
3. **Hide the key columns** from report view. Users should never see `geo_key`.
4. Set **data categories** on `state` / `city` / `postal_code` so maps work.
5. Sort `month_name` **by** `month_no`, or your axis reads Apr, Aug, Dec.

Import the aggregated tables, not raw everything — at 1M rows import mode is fine, but be
deliberate about it and write down why in the README.
</details>

## D3.3 — DAX: base measures and time intelligence

<details><summary><b>Hint 1 — nudge</b></summary>

**P§5** has all six patterns. Build in this order and each layer uses the one below:

1. Base: `Total Sales`, `Total Profit`, `Total Quantity`, `Order Count`, `Customer Count`
2. Ratios: `Margin %`, `AOV`, `Return Rate %` — always `DIVIDE`, never `/`
3. Time intelligence: `Sales LY`, `Sales YoY %`, `Sales MTD/YTD`, `Sales 3M MA`
4. Filter modifiers: `% of Total`, `Sales All Categories`
5. Domain: RFM counts, repeat rate, target attainment

Everything in a `_Measures` table with display folders. No implicit measures.
</details>

<details><summary><b>Hint 2 — method</b></summary>

```dax
Total Sales   = SUM ( fact_order_line[sales] )
Total Profit  = SUM ( fact_order_line[profit] )
Order Count   = DISTINCTCOUNT ( fact_order_line[order_id] )
Margin %      = DIVIDE ( [Total Profit], [Total Sales] )
AOV           = DIVIDE ( [Total Sales], [Order Count] )

Sales LY      = CALCULATE ( [Total Sales], SAMEPERIODLASTYEAR ( dim_date[date_key] ) )
Sales YoY %   = DIVIDE ( [Total Sales] - [Sales LY], [Sales LY] )

Sales 3M MA =
AVERAGEX (
    DATESINPERIOD ( dim_date[date_key], MAX ( dim_date[date_key] ), -3, MONTH ),
    [Total Sales]
)

Target Attainment % = DIVIDE ( [Total Sales], SUM ( fact_target[revenue_target] ) )
```

**`Order Count` uses `DISTINCTCOUNT`, not `COUNTROWS`** — the fact table is at line grain, so
`COUNTROWS` counts lines. Same trap as AOV in SQL (**P§8.3**), different language.

Return rate needs the same fan-out care as SQL:
```dax
Returned Orders = CALCULATE ( DISTINCTCOUNT ( fact_return[order_id] ) )
Return Rate %   = DIVIDE ( [Returned Orders], [Order Count] )
```
</details>

<details><summary><b>Hint 3 — near-solution</b></summary>

If `Sales LY` returns blank everywhere, work through this in order — it is almost always one of
these four, and they are the four things beginners miss:

1. `dim_date` is **not marked** as a date table → Table tools → Mark as date table → pick `date_key`.
2. The date table has **gaps** → it must be contiguous. Yours is, if you used `generate_series`.
3. The relationship runs `fact → dim` instead of `dim → fact` → check the arrow direction.
4. You are filtering on `fact_order_line[order_date]` on the axis instead of `dim_date[date_key]`.
   **Always put the dimension's column on the axis, never the fact's.** This one catches everybody.

Filter modifier pattern for share-of-total that stays correct as the user drills:
```dax
Category Share % =
DIVIDE (
    [Total Sales],
    CALCULATE ( [Total Sales], REMOVEFILTERS ( dim_product[category] ) )
)
```
</details>

## D3.4 — Row-level security

<details><summary><b>Hint 1 — nudge</b></summary>

**Modeling → Manage roles.** Create a role, give it a DAX filter on a table, test with
**View as → Role**.

The simplest defensible version for this brief: a `Restricted` role that cannot see customer
names. RLS filters *rows*, not columns — so to hide a column you either filter to a masked
dimension or add a masked display column and use that on visuals. Say which you chose and why
in the README; that trade-off is the interesting part.
</details>

<details><summary><b>Hint 2 — method</b></summary>

Masked display column on `dim_customer` (add in Power Query or as a calculated column):
```dax
Display Name =
LEFT ( dim_customer[customer_name], 1 ) & ". "
  & LEFT ( PATHITEM ( SUBSTITUTE ( dim_customer[customer_name], " ", "|" ), 2 ), 1 )
  & ". (" & dim_customer[customer_id] & ")"
```
Then a genuine RLS role for the region case, which is the more standard demonstration:
```dax
-- Role "West only", filter on dim_geography
[region] = "West"
```
Test with **View as → West only**. Every visual should re-compute. Screenshot that for the
write-up — it is good evidence.
</details>

## D3.5 — The DAX vs SQL gate

<details><summary><b>Hint 1 — nudge</b></summary>

Build a scratch page. One card per measure. Compare each against the number you recorded in
`analysis/questions.md` on Day 2. Ten measures minimum.

**Every mismatch is a real bug.** Do not rationalise one away as rounding — investigate it. This
gate exists because finding it now costs 10 minutes and finding it on Day 5 costs the write-up.
</details>

<details><summary><b>Hint 2 — the mismatches you will actually hit</b></summary>

In order of likelihood:

| Symptom | Cause | Fix |
|---|---|---|
| Order count / AOV too high in DAX | `COUNTROWS` instead of `DISTINCTCOUNT` on a line-grain table | `DISTINCTCOUNT(fact_order_line[order_id])` |
| Return rate far too high | Relationship `fact_return` → `fact_order_line` on `order_id` fanning out | Relate both to a shared order key, or keep return measures order-grain via `DISTINCTCOUNT` |
| YoY blank everywhere | Date table not marked, or fact's date column on the axis | See D3.3 Hint 3 |
| Margin % totals wrong at subtotal level | You averaged a row-level ratio | `DIVIDE(SUM(profit), SUM(sales))` — **P§3.2** |
| Share-of-total always 100% | Missing `REMOVEFILTERS` in the denominator | D3.3 Hint 3 |
| Target attainment blank for one region-year | The missing target row — this is correct behaviour | Show "no target set", do not invent one |

Record the comparison table in `analysis/dax-vs-sql.md`. It is a strong portfolio artefact: it
shows you tested your own work.
</details>

---

# Day 4 — dashboard

## D4.1 — Page 1, leading with margin recovery

<details><summary><b>Hint 1 — nudge</b></summary>

The change request promoted this. Page 1 must answer, top to bottom: *are we healthy, where is
margin leaking, and what would fixing it be worth?*

Layout that works: KPI row across the top (revenue, profit, margin %, YoY on each) → the
discount-vs-margin scatter with a break-even reference line → the trend with a 3-month moving
average → the counterfactual range as a single clear statement.

Resist putting everything on P1. A page answering one question well beats a page showing
everything.
</details>

<details><summary><b>Hint 2 — the scatter specifically</b></summary>

Sub-category on the details field, average discount on X, margin % on Y, revenue as bubble size.

Add a **constant line at Y = 0** (Analytics pane → Y-axis constant line). Everything below that
line is losing money. That single line does more explanatory work than any annotation, because
the audience reads "below the line = bad" without being told.

Colour by category, not by margin — you want the eye drawn to *position*, not to a second colour
scale competing with it.
</details>

## D4.2 — The returns waterfall

<details><summary><b>Hint 1 — nudge</b></summary>

Gross revenue → returned revenue → net revenue. A waterfall visual needs a category column and a
measure; build a small disconnected table with the step names and a `SWITCH` measure that returns
the right value per step.
</details>

<details><summary><b>Hint 2 — method</b></summary>

Create a disconnected table (Enter data): `Step` = {`Gross revenue`, `Returns`, `Net revenue`},
with a `Sort` column 1/2/3. Then:

```dax
Waterfall Value =
SWITCH (
    SELECTEDVALUE ( WaterfallSteps[Step] ),
    "Gross revenue", [Total Sales],
    "Returns",       -1 * [Returned Revenue],
    "Net revenue",   [Total Sales] - [Returned Revenue]
)
```
Sort the axis by the `Sort` column. Disconnected tables driving a `SWITCH` are a broadly useful
Power BI pattern — worth knowing beyond this one visual.
</details>

## D4.3 — The cohort heat matrix

<details><summary><b>Hint 1 — nudge</b></summary>

Matrix visual: cohort month on rows, `months_since` on columns, retention % on values, conditional
formatting as a colour scale on the values.

Import the cohort query result as its own table rather than trying to compute it in DAX. There is
no prize for doing it in DAX, and it will cost you an hour.
</details>

<details><summary><b>Hint 2 — reading it</b></summary>

Two things to check before you believe your own chart:

- **Column 0 must be 100%** across every row. If not, the cohort assignment is wrong.
- **The lower-right triangle should be empty.** Recent cohorts have not existed for 12 months yet.
  If it is populated, you have a join problem.

The finding is usually in *comparing rows*: one cohort's curve sitting visibly below its
neighbours means something changed in how those customers were acquired. Say which cohort and by
how much, not just "retention declines."
</details>

---

# Day 5 — prove it, grade it, ship it

## D5.1 — Running the user test

<details><summary><b>Hint 1 — how to actually do it</b></summary>

Find one person. They do not need to know the domain — that is arguably better.

Say exactly this: *"This is a sales dashboard. I'm not going to explain it. Tell me what you
think it says."* Then **stay silent**. Write down:

- every question they ask out loud
- everything they misread
- anything they never look at
- how long before they find the main point

Do not defend anything. Do not explain. The urge to say "no, that's the margin *rate*" is exactly
the finding — it means the label is wrong.

Fix the two worst things. Ignore the rest; you have 30 minutes, not a redesign.

> This is the closest thing to real stakeholder feedback available in a solo project, and almost
> no portfolio project has it. "I user-tested it and changed X because someone misread Y" is a
> strong, specific interview answer.
</details>

## D5.2 — The write-up

<details><summary><b>Hint 1 — structure</b></summary>

8-10 findings. Each is exactly three sentences:

1. **The number.** "Tables ran a -5.2% contribution margin in FY2021 on ₹X of revenue."
2. **The driver.** "62% of Table lines carried a discount above 16%, the point where margin
   crosses zero."
3. **The recommendation.** "Cap Table discounts at 15%, recovering ₹Y-₹Z depending on how many
   orders survive the change."

Then answer Priya's three questions explicitly, with headings. Then a short **Limitations**
section — what you could not determine and why. Naming your own limits reads as confidence, not
weakness, and it is the section interviewers probe.
</details>

<details><summary><b>Hint 2 — what makes a finding weak</b></summary>

| Weak | Why | Strong |
|---|---|---|
| "Revenue grew 15% YoY." | Descriptive. The chart said it. | "Revenue grew 15% but profit only 3%; the 12-point gap is entirely discount-driven — mean discount rose from 7.5% to 13.1% over the same period." |
| "Furniture has low margin." | No mechanism, no size. | "Furniture margin fell from 27% to 14.5%; two sub-categories (Tables, Bookcases) account for 78% of the decline." |
| "We should reduce discounts." | Not a decision — no threshold, no cost. | "Cap discounts at 20% on Tables and Bookcases. Upper bound ₹X recovered; lower bound -₹Y if every affected order churns." |

Every number must be reproducible from a query in `sql/`. If you cannot point at the query, delete
the sentence. That rule is the whole reason the question register has an Answer column.
</details>

## D5.3 — Grading yourself against the key

<details><summary><b>Hint 1 — how to score honestly</b></summary>

Open `_sealed/_DATASET-KEY.md`. Build a table in `README.md`:

| Planted signal | Found? | Where I found it / why I missed it |
|---|---|---|

Three categories, and the last two are the valuable ones:

- **Found** — you identified it independently.
- **Missed** — it was there, you did not see it. Write *why*. "I never grouped returns by
  sub-category, so I never saw the hotspots" is a real lesson.
- **Found but not planted** — you found something the generator was never told to produce.
  These are emergent, and they are the most interesting things in your write-up.

A score of 6/9 with honest explanations beats a claimed 9/9. Interviewers trust calibrated people,
and nobody believes a perfect score on a first project.
</details>
