# E-Commerce Sales & Customer Performance Analysis

> End-to-end analytics case study: a vague stakeholder ask → ~1M-row SQL star schema → Power BI
> dashboard → costed recommendations. Built as a **learning project** — the first of two.

| | |
|---|---|
| **Status** | Planned — 5-day sprint scheduled, not started |
| **Effort** | 4 full days + a half day (36 h) |
| **Stack** | PostgreSQL 16 · SQL (window functions, CTEs) · Power BI · DAX |
| **Data** | Superstore, scaled to **~1,000,000 order lines** (237 MB) across 2018-2021, plus a returns file and a deliberately messy regional targets file |
| **Start here** | [`STAKEHOLDER-BRIEF.md`](STAKEHOLDER-BRIEF.md) — the ask, as you would actually receive it |
| **Plan** | [`SPRINT-PLAN.md`](SPRINT-PLAN.md) · concepts in [`../_shared/ANALYST-PRIMER.md`](../_shared/ANALYST-PRIMER.md) · [`HINTS.md`](HINTS.md) when stuck |

## The business problem

An e-commerce company has grown revenue every year for four years, but profit has not kept pace.
Finance thinks it is discounting. Sales thinks it is the furniture line. Nobody has the numbers,
and three teams are guessing from three different spreadsheets.

The Head of Commercial needs a view she can navigate before a board meeting — and, more
importantly, **two or three decisions with rupee figures attached**, because someone will ask
*"how much"* and *"how do you know"*.

## The three questions the deliverable must answer

1. **What is happening?** — sales, product, customer and regional performance.
2. **Why is it happening?** — the mechanism behind each change, not just the change.
3. **What should the business do?** — 2-3 decisions, each with a number and a stated trade-off.

## How this project is set up, and why

Four things here are deliberately harder than a typical portfolio project, because they are the
four things portfolio projects usually skip:

| | What it looks like | Why |
|---|---|---|
| **You write the questions** | `analysis/questions.md` starts empty; you derive it from a vague email | Turning ambiguity into answerable questions is the most-tested analyst skill, and a pre-filled register cannot teach it |
| **You find the defects** | Nothing tells you what is broken in the data | Seven defects were injected from a menu of sixteen, at rates of 0.04-0.6%. Real profiling is hunting unknown unknowns |
| **The requirements change** | A sealed change request opens on Day 3 | Every real project has one. Practising the re-scope once, in private, is worth a lot |
| **Someone else uses it** | A 30-minute user test on Day 5 | The gap between "I understand my dashboard" and "a stranger understands it" is where most of them fail |

Sealed files (`_SEALED-*`, `_sealed/`) stay closed until the day the plan says. There is no way to
un-know what is in them, and being told the answers turns the project into a tutorial.

## What this builds

```
orders.csv (1M lines)  ─┐
returns.csv            ─┼─→  staging (all text)  →  core (typed, star schema)  →  SQL analysis
targets.csv (messy)    ─┘         │                        │                            │
                                  │                   indexes + gate                    │
                                  ▼                        ▼                            ▼
                            data-quality log       reconciliation           Power BI · DAX · RLS
                                                                                        │
                                                                     4 pages + written recommendations
```

Seven tables: `dim_date`, `dim_customer`, `dim_product`, `dim_geography`, `fact_order_line`
(line grain), `fact_return` (**order** grain — the main modelling trap), `fact_target`.

## Data provenance — read this before quoting it anywhere

The base data is the **Tableau Sample Superstore** extract (9,994 real order lines). It has been
**scaled to ~1M rows by `_sealed/build_dataset.py`**, which:

- generates 110,000 synthetic customers and ~338,000 orders across the original 2018-2021 window,
  reusing the real product catalogue, geography and category structure
- plants business signals (discount drift, per-sub-category margin break-even points, divergent
  regional growth and margin, seasonality, return hotspots, a weak acquisition cohort)
- injects a random subset of data-quality defects
- generates the regional targets file with realistic maintenance damage

Say exactly this if anyone asks: **"Superstore's real product and geography structure, scaled to
~1M synthetic transactions with deliberately planted signals and defects."** Do not describe it as
production data.

## Repo layout

```
sql/          build + analysis scripts, numbered in run order
analysis/     question register, data-quality log, learning log, findings
python/       (optional) profiling helpers
powerbi/      the .pbix
assets/       dashboard screenshots for the write-up
_sealed/      dataset builder + key — DO NOT OPEN until Day 5
```

## Definitions I am committing to

*(fill on Day 1 — see `analysis/data-quality-log.md`. **P§3.4**: writing these down before someone
else picks them for you is the cheapest credibility you will ever buy.)*

| Term | Definition |
|---|---|
| Revenue | |
| Margin | |
| Return rate | |
| Repeat customer | |

## Findings

*(written Day 5 — 8-10 findings, each with the number, the driver, and the recommendation)*

## Self-assessment

*(Day 5 — planted signals found vs missed vs found-but-never-planted, with reasons. An honest
6-of-9 with explanations is more convincing than a claimed clean sweep.)*

## Notes for future me

- Every number quoted here must be reproducible from a query in `sql/`. If it is not, delete it.
- Commit after every block. `git log` is proof you did this over five days.
- The dataset is regenerable but **do not regenerate mid-sprint** — the seed is random per build,
  so a rerun gives different data and invalidates every number you have written.
