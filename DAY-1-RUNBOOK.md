# Day 1 runbook — the mechanics

[`SPRINT-PLAN.md`](SPRINT-PLAN.md) says *what* to build. [`HINTS.md`](HINTS.md) helps when you are
stuck on *how to think about it*. This file is only about **where to type things and how to run
them** — the plumbing, so plumbing never costs you a build block.

> Deliberately mechanical. It contains no analytical hints and does not tell you what is wrong
> with the data. That is what Day 1 is for.

---

## Your toolchain — three tools, three jobs

| Tool | For | How to open |
|---|---|---|
| **VS Code** | **Writing** the `.sql` files. Where you spend most of Day 1 | `code "C:/Users/coral/Documents/PBI Dashboads/04-Projects/ecommerce-sales-analysis"` |
| **psql** | **Running** whole script files, and the only thing that can run `\copy` | see below |
| **pgAdmin 4** | **Exploring** — a result grid you can scroll and export | Start Menu → PostgreSQL 16 → pgAdmin 4 |

The division that matters: **build scripts (01-07) run in psql; exploratory queries (02, 10+) run
in pgAdmin.** Build scripts must run start-to-finish reproducibly. Exploration needs a grid you
can read.

You do not have DBeaver and do not need it. Do not install it now — that is 30 minutes of sprint
time for no gain.

### The one hard rule

`\copy` is a **psql client command, not SQL**. pgAdmin cannot run it and neither can VS Code.
Paste `01_staging_load.sql` into pgAdmin and you get a syntax error on the `\copy` line.

Every tutorial shows `COPY` instead. That one is **server-side** — it runs as the Postgres service
account, which cannot read your Documents folder, and you get `Permission denied`. That is
expected. `\copy` is the answer.

---

## Before the clock starts — 5 minutes

Open two windows and leave them open all day.

**1. VS Code** at the project root:
```bash
code "C:/Users/coral/Documents/PBI Dashboads/04-Projects/ecommerce-sales-analysis"
```

**2. A terminal** parked in the project directory:
```bash
cd "C:/Users/coral/Documents/PBI Dashboads/04-Projects/ecommerce-sales-analysis"
```

Test the connection before you need it:
```bash
psql -h 127.0.0.1 -U postgres -d ecommerce -c "\dn"
```
You should see `core`, `public`, `staging`.

> **The `-h 127.0.0.1` is not optional.** Your `pg_hba.conf` trusts TCP connections from localhost
> but requires a password for local socket connections. Drop the `-h` and it prompts for a
> password you never set.

---

## Where the data is

```
02-Datasets/Raw/ecommerce-scaled/
    orders.csv     ~237 MB   ~1,000,000 order lines, 21 columns
    returns.csv    ~0.6 MB   returned order IDs
    targets.csv    ~1 KB     regional revenue targets — maintained by three people, and it shows
```

Built by `python _sealed/build_dataset.py` on Day 0. If you need to rebuild, **do not** do it
mid-sprint: each build uses a fresh random seed, so a rerun changes every number you have already
written down.

---

## The two ways to run SQL

**Run a whole file** (build scripts):
```bash
psql -h 127.0.0.1 -U postgres -d ecommerce -v ON_ERROR_STOP=1 -f sql/01_staging_load.sql
```

`ON_ERROR_STOP=1` matters. Without it psql keeps going after an error and you get a half-applied
script — some tables created, some not, no obvious sign anything went wrong.

**Sit inside psql** (poking around):
```bash
psql -h 127.0.0.1 -U postgres -d ecommerce
```

| Command | Does |
|---|---|
| `\dt staging.*` | list tables in staging |
| `\d staging.orders` | describe a table's columns and types |
| `\i sql/02_profiling.sql` | run a file from inside the session |
| `\x` | toggle expanded output — essential for wide rows |
| `\timing` | show how long each query took. **Turn this on and leave it on today** |
| `\copy ...` | client-side file load |
| `\q` | quit |

---

## The working loop

For every block in the plan:

1. Open the file in VS Code.
2. Write the SQL.
3. Run it — psql for build, pgAdmin for exploration.
4. Run the check at the bottom of the file.
5. **Write what you found** into `analysis/` — the register, the DQ log, or the learning log.
6. `git add -A && git commit -m "..."`.
7. Only then move on.

Steps 5 and 6 are the ones people skip, and they are what make this a portfolio piece rather than
a folder of queries.

### Commit messages

One per block. Keep them boring and factual:

```
feat(staging): load orders, returns, targets as text
chore(profile): column-level profile across all 21 columns
fix(clean): quarantine non-positive quantity rows with reason
feat(model): dim_date, dim_customer, dim_product, dim_geography
feat(model): fact_order_line at line grain, fact_return at order grain
perf(index): composite index on (product_id, order_date)
test(gate): reconciliation — clean + rejected = staged
```

---

## Working at 1M rows — three habits

The old version of this project ran on 9,994 rows, where everything is instant. At 1M, three
things change:

1. **`\timing` on, always.** You want to notice a query going from 200 ms to 40 s the moment it
   happens, not after you have built three more on top of it.
2. **`LIMIT` while developing.** Get the query shape right on `LIMIT 1000`, then remove it.
3. **A query taking minutes is a missing index, not a slow computer.** Stop and `EXPLAIN ANALYZE`
   it. That is the Day 1 index block, and the before/after numbers are a portfolio artefact.

Loading 237 MB via `\copy` takes roughly 20-60 seconds. If it takes 10 minutes, you are probably
inserting row by row somewhere.

---

## End of Day 1 — you are done when

- [ ] `staging` holds all three files, and counts tie to the CSVs
- [ ] `analysis/data-quality-log.md` has a row per defect, each with a count, a detection method
      and a decision
- [ ] The grain is written down as a sentence, for **both** fact tables
- [ ] Seven tables in `core`, FKs resolving, no orphans
- [ ] Indexes created, with one `EXPLAIN ANALYZE` before/after pair recorded
- [ ] `07_reconciliation.sql` returns **all PASS**
- [ ] The reconciliation record in the DQ log is filled in
- [ ] Everything committed

---

## When something breaks

| Error | What it means |
|---|---|
| `could not open file ... Permission denied` | You used `COPY` instead of `\copy`. Server-side vs client-side |
| `syntax error at or near "\"` | You ran a `\copy` line in pgAdmin. Use psql |
| `password authentication failed` | You dropped `-h 127.0.0.1`. Local socket wants a password; TCP is trusted |
| `relation "orders" does not exist` | `search_path` resolves against `core` first. Qualify it: `staging.orders` |
| `invalid input syntax for type numeric: ""` | A blank CSV field became `''`, not NULL. Handle empty strings explicitly in the cast |
| `invalid input syntax for type numeric: "1,234.56"` | Strip the separator before casting: `replace(x, ',', '')::numeric` |
| `invalid input syntax for type date: "14-07-2026"` | Not every date is ISO. Branch on the shape before casting |
| `byte sequence ... has no equivalent in "WIN1252"` | The `\copy` is missing `ENCODING 'UTF8'`. The CSVs are UTF-8; a Windows console defaults `client_encoding` to WIN1252. Do **not** "fix" it by declaring WIN1252 — that makes it worse |
| Numbers off by 0.0000001 at the gate | You cast money to `float`. Use `numeric` |
| A query has been running for 5 minutes | Cancel it (`Ctrl-C`), `EXPLAIN ANALYZE` it, add the index the plan is asking for |
| `out of memory` in Power BI on import | You are importing raw where an aggregate would do. Be deliberate about what you import |

Ask me to review a query or debug an error any time — that is what I am useful for here. I am
deliberately not writing the analysis SQL for you, because being able to say *"I wrote these"* is
the entire point.
