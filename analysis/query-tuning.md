# Query tuning record

Every number here came from `EXPLAIN (ANALYZE, BUFFERS)` on this machine, against
`core.fact_order_line` (996,567 rows, 122 MB heap). Run `sql/06_indexes.sql` to reproduce.

PostgreSQL 16 · `shared_buffers` 128 MB · `work_mem` 4 MB (default) unless stated.

---

## 1. The build that was not slow, it was mis-planned

**Symptom.** `05_dimensional_model.sql` ran for **over 10 minutes** and was still going. The
tempting conclusion — "a million rows is just slow" — was wrong, and worth resisting.

**Diagnosis.** `pg_stat_activity` showed the backend `active` with no wait event, i.e. burning
CPU rather than waiting on disk. The fact build joins four dimensions, three of which are created
by `CREATE TABLE AS` *earlier in the same script*.

> A table created by `CREATE TABLE AS` has **no planner statistics** until it is analysed.
> With no statistics the planner assumes roughly one row, picks a **nested loop**, and then
> re-scans a 107,688-row dimension once per fact row.

**Fix.** Two lines, in this order of importance:

| Change | Why |
|---|---|
| `ANALYZE core.dim_customer / dim_product / dim_geography` immediately after creating them | Gives the planner real row counts, so it chooses a hash join |
| `SET LOCAL work_mem = '256MB'` | The dim_customer hash table does not fit in 4 MB and spills to disk in batches. `SET LOCAL` reverts at `COMMIT`, so no server config is touched |

| | Before | After |
|---|---|---|
| `05_dimensional_model.sql`, whole script | > 600 s (cancelled twice) | **32.5 s** |

**What this is worth saying in an interview:** the first instinct on a slow query is to add an
index. The index would not have helped here at all. The planner had bad information, and the fix
was to give it good information. `ANALYZE` after a bulk load is not housekeeping — it is the
difference between a hash join and a nested loop.

---

## 2. Indexes: what they fixed, and what they did not

Three representative queries, each measured before and after `06_indexes.sql`.

| # | Query | Before | After | Change | Plan node that changed |
|---|---|---|---|---|---|
| Q1 | Monthly revenue + margin for one sub-category in one region (`Tables` × `West`) — what a dashboard slicer issues | 127.2 ms | 135.9 ms | **none** | Fact still parallel-seq-scanned; only the two dimension scans became index scans |
| Q2 | `SUM(sales), SUM(profit), COUNT(DISTINCT order_id)` over the whole fact table — the Page 1 KPI row | **7,830.0 ms** | **1,736.7 ms** | **4.5× faster** | `Seq Scan` + hash aggregate → `Index Scan using ix_fol_order`, which returns rows already ordered by `order_id` so the distinct count no longer needs a 996k-row sort |
| Q3 | Margin by sub-category for lines discounted ≥ 50% — the headline analysis | 140.0 ms | 86.5 ms | 1.6× faster | `Parallel Seq Scan` → `Bitmap Index Scan on ix_fol_high_discount` (partial index, 3.7% of rows) |

### The honest finding: Q1 did not improve, and that is correct

Q1 filters on *dimension* attributes, so the fact table has to be read regardless — the filter
only bites after the join. A query that touches a large share of a table is **supposed** to
sequential-scan it; a sequential scan reads pages in order and a 996k-row index scan would be
slower, not faster. Postgres knows this, which is why it ignored the new indexes here.

The lesson generalises: **an index earns its place on selectivity, not on table size.** Q3 is fast
because 3.7% of rows match. Q2 got faster for a different reason again — not selectivity, but
ordering: the index supplied a sorted stream and removed the sort, not the scan.

### What the indexes cost

| | |
|---|---|
| Heap | 122 MB |
| Indexes | 108 MB |
| Total | 230 MB |

Indexes are **89% of the heap size**. That is the half of the answer people leave out. On a
read-only analytical table refreshed nightly that is an easy trade; on a write-heavy OLTP table it
would not be, because every index is also a write amplification on every insert.

| Index | Size | Justification |
|---|---|---|
| `ix_fol_date_covering (date_key) INCLUDE (sales, profit, quantity)` | 39 MB | Most-run shape: measures for a date slice, answerable index-only |
| `ix_fol_order (order_id)` | 17 MB | The Q2 win — AOV, order counts, returns link |
| `ix_fol_customer` | 9.2 MB | Top-customer table, RFM |
| `ix_fol_product` | 7.2 MB | Page 2 |
| `ix_fol_date` | 7.1 MB | Date slicer |
| `ix_fol_geography` | 7.0 MB | Page 3 map |
| `ix_fol_high_discount (discount, product_key) WHERE discount >= 0.50` | 1.2 MB | Partial: small because only 3.7% of rows qualify. The best value per megabyte in the file |
| `ix_fr_date` | 232 kB | Returns trend |

**Not indexed:** `sales`, `profit`, `quantity`. Nothing filters on a measure — they are only ever
aggregated — and an index on a column you exclusively `SUM` is dead weight.

---

## 3. Reproducing this

```
psql -h 127.0.0.1 -U postgres -d ecommerce -f sql/06_indexes.sql
```

To measure a "before" without dropping an index, disable the plan type rather than the index:

```sql
SET enable_bitmapscan = off;
SET enable_indexscan  = off;
EXPLAIN (ANALYZE) <your query>;
```

That is how the Q3 baseline above was taken after the index already existed — cheaper and less
destructive than dropping and rebuilding a 1.2 MB index, and it gives the planner's honest
alternative rather than a guess at one.
