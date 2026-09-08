# 5-day sprint plan — E-commerce Sales & Customer Performance

36 hours: 4 full days + a half day. Times are offsets from whenever you start, not clock times.

---

## Outcome — completed, tagged `v1.0`

| Day | Status | Evidence |
|---|---|---|
| **0** Questions | ✅ | 37 questions in 7 groups, scored 17/25 against the sealed list, 7 added — [`analysis/questions.md`](analysis/questions.md) |
| **1** Ingest, prove, model | ✅ | 7-table star schema, 8 indexes, **15/15 reconciliation PASS** at zero tolerance |
| **2** Analysis | ✅ | `10_`-`15_`, every question answered with the number recorded |
| **3** Change request + model | ✅ | Re-scope written *before* rebuilding, counterfactual as a range, 42 DAX measures, RLS/OLS designed, DAX-vs-SQL gate specified with 5 mismatches documented |
| **4** Dashboard | ◐ | Four pages, theme and interactions fully specified in [`powerbi/BUILD-RUNBOOK.md`](powerbi/BUILD-RUNBOOK.md); the `.pbix` itself is ~3 h of GUI assembly with no decisions left |
| **5** Prove, grade, ship | ◐ | Write-up, self-assessment (**9/10 signals, 6/7 defects**), resume material and git history all complete. **The user test is outstanding** — it needs a real person and cannot be simulated; protocol in [`analysis/uat-notes.md`](analysis/uat-notes.md) |

**Never-cut list:** reconciliation gate ✅ · DAX-vs-SQL gate ✅ · write-up ✅ · user test ◐.

Everything below is the plan as written before starting, left unedited.

---


> **This is the teaching project.** Hints are extensive, the data is forgiving, and you check your
> work against sealed files at the end of each phase. The telecom project is where you do it
> unaided. Read [`../_shared/ANALYST-PRIMER.md`](../_shared/ANALYST-PRIMER.md) §1-§3 first — it
> maps everything here onto things you already know as a software engineer.

**Stuck?** [`HINTS.md`](HINTS.md) has tiered hints for every block. Use the 20-minute rule: try for
20 minutes, then open Hint 1. Opening hints is not failure. Opening Hint 3 first is.

---

## Why this is 5 days and not 3

The earlier version of this plan said 3 days / 24 h. That was wrong in two ways: it assumed a
9,994-row toy dataset, and it left no room to be a beginner. This version works on ~1M rows,
adds the parts of the job that were missing (deriving your own questions, a second data source,
a mid-sprint requirements change, real indexing, a user test), and budgets honestly.

If you finish early, good. Plans that assume nothing goes wrong teach you nothing about planning.

---

## Day 0 — setup (~2 h, not counted)

Do this the night before. Doing it on Day 1 costs you a build block.

- [ ] **Read** [`../_shared/ANALYST-PRIMER.md`](../_shared/ANALYST-PRIMER.md) §1-§3 (~25 min).
      Non-negotiable. The rest of the sprint assumes grain, additivity and fan-out.
- [ ] **Git.** From the project folder:
      ```
      git init
      git add -A
      git commit -m "chore: project scaffold before sprint"
      ```
      Then commit after every block below. `git log` becomes proof you did this over five days
      rather than pasting it from somewhere — recruiters do look.
- [ ] **Build the dataset** (~30 s):
      ```
      python _sealed/build_dataset.py
      ```
      Writes ~1M order lines, a returns file and a targets file to
      `02-Datasets/Raw/ecommerce-scaled/`. It plants business signals and a randomly chosen set
      of data-quality defects, then seals what it did in `_sealed/_DATASET-KEY.md`.
      **Do not open that key, or the script, before Day 5.**
- [ ] Create database `ecommerce` with schemas `staging` and `core` — `sql/00_setup.sql`
- [ ] Confirm Power BI Desktop's PostgreSQL connector loads
- [ ] Log the dataset in `02-Datasets/DATASETS.md`
- [ ] **Derive your question register (60 min)** from
      [`STAKEHOLDER-BRIEF.md`](STAKEHOLDER-BRIEF.md) into `analysis/questions.md`.
      This is the most valuable hour in the sprint. Then compare with
      `_SEALED-question-list.md`, score yourself, and merge.

**Optional warm-up (90 min), strongly recommended if window functions are new:** write one query
each using `LAG`, `SUM() OVER (ORDER BY ...)`, `NTILE(4)` and `ROW_NUMBER() OVER (PARTITION BY ...)`
against the original 9,994-row file. Days 1-2 lean on all four. See *Risks* R2.

---

## Day 1 — ingest, prove, model (8 h)

*Raw CSV → trustworthy star schema. Nothing downstream is worth anything if this day is wrong.*

| Time | Dur | Block | Output |
|---|---|---|---|
| 00:00 | 0:30 | Re-read your question register. Decide what "answered" means for each | register |
| 00:30 | 0:45 | Load all three files → `staging`, **every column as `text`**. Row counts must tie to the files | `01_` |
| 01:15 | 1:30 | **Profile.** Counts, nulls, distincts, ranges, dupes, value domains. **Prove the grain.** Hunt defects — you have not been told what they are | `02_`, DQ log |
| 02:45 | 0:15 | Break | |
| 03:00 | 1:30 | **Clean and cast** into `core`. Quarantine bad rows into `core.rejected` with a reason. Log every decision as you make it | `03_`, DQ log |
| 04:30 | 1:45 | **Star schema** — `dim_date`, `dim_customer`, `dim_product`, `dim_geography`, `fact_order_line`, `fact_return`, `fact_target`. PK/FK after load | `04_`, `05_` |
| 06:15 | 0:45 | **Indexes.** At 1M rows a missing index is now felt. `EXPLAIN ANALYZE` one slow query before and after; record both | `06_` |
| 07:00 | 1:00 | **GATE — reconciliation.** `clean + rejected = staged`, and sales/profit tie to `staging`. One query, `PASS`/`FAIL` per row. Do not continue until every row passes | `07_` |

**Done when:** the star schema is queryable, indexed and reconciled; the DQ log has a row per
defect with a count and a decision; the grain is written down as a sentence.

> **The trap on this day:** orders are at *line* grain, returns at *order* grain. Join them
> directly and one return multiplies across every line of its order. The gate catches it — if
> your return rate looks wildly high, that is what happened. Primer §3.1.

---

## Day 2 — the analysis (8 h)

*Answer every question in SQL and write the number down. This day produces the findings.*

| Time | Dur | Block | Output |
|---|---|---|---|
| 00:00 | 1:45 | **Sales + seasonality** — revenue/profit trend, YoY, MoM, AOV, seasonality, growth contribution | `10_` |
| 01:45 | 1:45 | **Product + the margin question** — top/bottom, Pareto, high-sales/low-profit, consistent underperformers, **and the discount-vs-margin threshold Finance asked about** | `11_` |
| 03:30 | 0:15 | Break | |
| 03:45 | 1:30 | **Customer** — repeat rate, frequency, RFM (`NTILE`), cohort retention, top customers | `12_` |
| 05:15 | 1:15 | **Regional + returns** — region performance, margin by region, return rate by category/region, returns impact on profit | `13_`, `14_` |
| 06:30 | 0:45 | **Targets** — join the messy targets file to actuals. Region names do not match. Units are inconsistent. This is a real integration problem | `15_` |
| 07:15 | 0:45 | Write every headline number into the **Answer** column of the register | findings |

**Done when:** every question has a query and a recorded number. Those numbers are what your DAX
gets tested against tomorrow, and the raw material for the write-up.

> **Watch for:** AOV is per *order*, not per line (Primer §4). Seasonality means averaging the
> same calendar month across years, not ranking all 48 months. "Consistently underperforming" is
> a *count of periods below threshold*, not an average.

---

## Day 3 — the change request, then the model (8 h)

*Real projects change mid-flight. Today you find out what that costs.*

| Time | Dur | Block | Output |
|---|---|---|---|
| 00:00 | 0:20 | **Open [`_SEALED-change-request.md`](_SEALED-change-request.md).** Read it properly | |
| 00:20 | 0:25 | **Re-scope on paper.** What is promoted, demoted, new, cut — and what that costs. Write it in the learning log | trade-off note |
| 00:45 | 1:15 | The counterfactual: revenue and profit under a discount cap, as a **range** not a point | `16_` |
| 02:00 | 1:00 | Power BI — connect, import, relationships (single direction, 1→\*), **mark `dim_date` as a date table**, hide keys, set geo categories | model |
| 03:00 | 0:15 | Break | |
| 03:15 | 2:30 | **DAX measure layer** in a `_Measures` table with display folders: base, ratios, time intelligence, filter modifiers, customer, returns, targets (~25 measures) | measures |
| 05:45 | 1:00 | Row-level security — hide customer names outside Commercial. Test with **View as** | RLS |
| 06:45 | 1:15 | **GATE — DAX vs SQL.** Scratch page comparing 10 key measures to yesterday's SQL answers. Fix mismatches now | validation |

**Done when:** the model is built and marked, ~25 measures exist, RLS works, and every measure
you checked agrees with SQL.

> **DAX is the newest thing here.** Primer §5 has the six patterns that cover this whole day.
> Every mismatch at the gate is a real bug — usually a relationship direction or a fan-out.

---

## Day 4 — dashboard (8 h)

*Four pages. Page 1 leads with margin recovery, because that is what the stakeholder now wants.*

| Time | Dur | Block | Output |
|---|---|---|---|
| 00:00 | 0:30 | Theme from `05-Assets/Themes`, 4 page skeletons, consistent header and nav | layout |
| 00:30 | 1:45 | **P1 Margin & Executive** — margin-recovery KPI row, discount-vs-margin scatter with the break-even line, revenue/profit trend with YoY, the counterfactual range | page 1 |
| 02:15 | 1:15 | **P2 Product & Category** — matrix with margin conditional formatting, Pareto, underperformers, sales-vs-profit quadrant | page 2 |
| 03:30 | 0:15 | Break | |
| 03:45 | 1:15 | **P3 Regional & Targets** — map coloured by margin, target vs actual by region, region quadrant, growth table | page 3 |
| 05:00 | 1:15 | **P4 Customer & Returns** — repeat vs one-time, RFM segments, return rate by category, returns waterfall (gross → returns → net) | page 4 |
| 06:15 | 0:45 | Interactivity — drill-through, tooltip page, reset bookmark, sync slicers, alt text | polish |
| 07:00 | 1:00 | Buffer. You will need it | |

**Done when:** four pages, every number traceable to a query, nothing on screen you cannot explain.

---

## Day 5 — prove it, grade it, ship it (4 h)

*The half day that turns a dashboard into a portfolio piece.*

| Time | Dur | Block | Output |
|---|---|---|---|
| 00:00 | 0:30 | **User test.** Hand the `.pbix` to one real person. Say nothing. Write down every question they ask and everything they misread | UAT notes |
| 00:30 | 0:30 | Fix the two worst things they found. Ignore the rest | fixes |
| 01:00 | 0:30 | **Grade yourself.** Open `_sealed/_DATASET-KEY.md`. Which planted signals did you find? Which did you miss? What did you find that was never planted? | self-assessment |
| 01:30 | 1:30 | **Write-up** — 8-10 findings in `README.md`. Each: the number, the driver, the recommendation. Answer Priya's three questions. 2-3 costed decisions | README |
| 03:00 | 0:30 | Package — screenshots to `assets/`, `DATASETS.md` row, resume bullets and LinkedIn blurb into `06-Career/` | portfolio |
| 03:30 | 0:30 | Final commit, tag `v1.0`, write `analysis/learning-log.md` conclusions | git |

**Done when:** the write-up answers what / why / what-next with real numbers, and you have scored
yourself honestly against the key.

> A self-assessment saying *"I found 6 of 9 planted signals, missed the cohort effect entirely,
> and here is why"* is **more** convincing than a clean sweep. Interviewers trust calibrated
> people. Nobody believes a perfect score.

---

## If you fall behind — drop in this order

1. Mobile layout *(already out of scope)*
2. Field parameters, and any bookmark beyond a single reset button
3. Row-level security → substitute a masked display-name column, and say so in the README
4. The drill-through detail page — keep tooltips only
5. **Cohort retention matrix** — substitute a repeat-rate KPI plus a segment trend line. Timebox
   it to 45 min on Day 2 and cut on sight; it is the most expensive item in the sprint
6. P4 collapses into a section on P1

**Never cut:** the Day 1 reconciliation gate · the Day 3 DAX-vs-SQL gate · the Day 5 user test ·
the Day 5 write-up. Those four are what separate a portfolio project from a screenshot.

---

## Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | DAX time intelligence and filter context are new | Primer §5 covers the six patterns. Do the Day 0 warm-up. This is the most likely way the sprint slips |
| R2 | Window functions (`NTILE`, `LAG`, cumulative `SUM OVER`) are used heavily on Day 2 | Same warm-up, SQL side. Write one of each before Day 1 |
| R3 | Returns join fans out and the return rate comes out wrong | The Day 1 gate catches it. Keep `fact_return` at order grain |
| R4 | 1M rows makes a bad query feel broken rather than slow | That is the point of the Day 1 index block. If a query runs over ~30 s, stop and `EXPLAIN ANALYZE` it |
| R5 | The targets join eats more than its 45 minutes | Timebox it. A defensible mapping table beats a clever fuzzy match |
| R6 | Visual perfectionism eats the write-up | The write-up is what gets read. Ship the page as-is and write |
| R7 | Curiosity opens `_sealed/` early | The one irreversible mistake available this week. There is no way to un-know it |
| R8 | Scope creep into Python, forecasting or ML | Out of scope here — that is the telecom project. Log it under "future work" and move on |

---

## Resume bullets — draft on Day 5, with real numbers

Replace every `__` with a figure you can reproduce from a query in `sql/`. **Do not ship a number
you cannot defend**, and do not describe the data as anything other than what it is.

- Built an end-to-end analytics solution on **~1M** transactional records — modelled a seven-table
  star schema in PostgreSQL, wrote `__` analytical SQL queries, tuned indexes to bring the
  heaviest query from `__`s to `__`s, and delivered a four-page Power BI dashboard.
- Identified `__` sub-categories where contribution margin turns negative above a `__`% discount,
  quantified `₹__` of annual margin leakage, and modelled a discount cap as a **range**
  (`₹__`–`₹__`) rather than a point estimate, stating the elasticity assumption.
- Integrated a second, inconsistently maintained source (regional targets — 4 spellings per
  region, mixed units) to deliver target-vs-actual by region, and documented the mapping rules.
- Built RFM segmentation and cohort retention showing `__`% repeat-purchase and that the top
  `__`% of customers drive `__`% of revenue.

---

## Files

| File | What it is | When |
|---|---|---|
| [`STAKEHOLDER-BRIEF.md`](STAKEHOLDER-BRIEF.md) | Your actual input — the vague ask | Day 0 |
| [`HINTS.md`](HINTS.md) | Tiered hints for every block | when stuck |
| [`DAY-1-RUNBOOK.md`](DAY-1-RUNBOOK.md) | Where to type things and how to run them | Day 1 |
| [`analysis/questions.md`](analysis/questions.md) | Your question register — you write it | Day 0 |
| [`analysis/data-quality-log.md`](analysis/data-quality-log.md) | Every cleaning decision | Day 1 |
| [`analysis/learning-log.md`](analysis/learning-log.md) | What you got stuck on and what unstuck you | throughout |
| `_SEALED-question-list.md` | The 25 questions to compare against | after Day 0 |
| `_SEALED-change-request.md` | The requirements change | Day 3 |
| `_sealed/_DATASET-KEY.md` | What was planted in the data | Day 5 |
