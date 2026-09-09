# Power BI build runbook

Everything needed to assemble `ecommerce-sales-analysis.pbix` from the finished
PostgreSQL model. Every number quoted on a page traces to a query in `../sql/`, and
every measure is in [`measures.dax`](measures.dax).

> **Read this first — most of what follows is already built.**
>
> `ecommerce-sales-analysis.pbip` in this folder is a **Power BI Project**: the same
> thing as a `.pbix`, stored as text instead of as a binary. It already contains the
> model, all 59 measures in their display folders, the relationships, both what-if
> parameters, both security roles and a four-page report.
>
> **To use it:** double-click `ecommerce-sales-analysis.pbip` ▸ Power BI Desktop opens
> it ▸ enter your PostgreSQL credentials when prompted ▸ `File ▸ Save as` ▸ `.pbix`.
>
> Everything below is the **manual build**, kept for two reasons: it is the fallback if
> the generated report does not open (see `_fallback-blank-report/README.md`), and it
> is the record of *why* each setting is what it is — which the `.pbip` cannot tell you.
> Budget ~3 hours if you build it by hand.

## What the generated project already does for you

| Runbook phase | Already in the `.pbip`? | Notes |
|---|---|---|
| 0.1 Get data | ✅ | Seven `core.*` tables plus the `v_subcat_breakeven` view, Import mode, typed in M so the declared types always match |
| 0.2 Power Query | ✅ | `Table.TransformColumnTypes` per table — money as `Currency.Type` (fixed decimal), dates as `type date` |
| 0.3 Relationships | ✅ | All 7, many-to-one, single direction. `fact_target` deliberately disconnected — see the `Revenue Target` measure |
| 0.4 Mark as date table | ✅ | `dim_date` carries `dataCategory: Time` and `date_key` is `isKey` |
| 0.5 Hide / sort / categorise | ✅ | Keys hidden, `month_name`→`month_no`, geo data categories set |
| 0.6 The 59 measures | ✅ | 9 display folders, format strings, and the SQL value each must equal in the description |
| 0.7 What-if parameters | ✅ | `Discount Cap` and `Survival Rate` as calculated tables + their `SELECTEDVALUE` measures |
| 0.8 Theme | ❌ | **Do this yourself:** `View ▸ Themes ▸ Browse` ▸ `theme.json`. One click; not worth the risk of embedding it |
| Phases 1-4, pages | ✅ | 38 visuals across 4 pages — but see the caveat below |
| Phase 5 interactivity | ❌ | Drill-through, tooltip page, bookmarks, sync slicers, alt text are yours |
| Phase 6 OLS | ❌ | Needs Tabular Editor. RLS roles *are* in the file |
| Phase 7 the gate | ❌ | **Do not skip.** `dax-vs-sql-gate.md` |

**The caveat, stated plainly.** The model I am confident about. The report was authored as
PBIR text and validated statically — all 68 field references resolve against the model and
every JSON file parses — but it was never opened in Power BI Desktop before delivery. If a
visual renders oddly, fix it in the GUI; if the report as a whole is rejected, swap in
`_fallback-blank-report/` and you still have the entire model.

**Page order is deliberate and reflects the Day 3 change request**: margin recovery
is Page 1. Customer analytics was demoted to Page 4 and kept only because it was
already built — see `../analysis/learning-log.md` for the written trade-off.

---

## Phase 0 — connect and model (45 min)

### 0.1 Get data

`Home ▸ Get data ▸ PostgreSQL database`

| Field | Value |
|---|---|
| Server | `127.0.0.1` |
| Database | `ecommerce` |
| Data Connectivity mode | **Import** |

**Why Import and not DirectQuery.** The data is a static four-year extract that
never refreshes; Import gives VertiPaq compression, sub-second visuals and full DAX
(time intelligence is crippled under DirectQuery). DirectQuery would be the right
call if this were live operational data or if the model exceeded memory. It is 122 MB
of heap that compresses to roughly 60 MB — Import, comfortably.

Select exactly these seven tables and nothing else:

```
core.dim_date          core.fact_order_line
core.dim_customer      core.fact_return
core.dim_product       core.fact_target
core.dim_geography
```

Do **not** import `staging.*`, `core.orders_clean`, `core.returns_clean`,
`core.rejected` or `core.region_map`. They are build scaffolding; importing them
doubles the model size and gives a report author two plausible-looking tables that
disagree.

### 0.2 Power Query — the only steps needed

The heavy lifting is already done in SQL. That is the point: transformations belong
in the layer that can be version-controlled, tested and reconciled, not in a Power
Query pane nobody else can read. Only these:

1. Rename each query to drop the schema prefix (`core dim_date` → `dim_date`).
2. On `fact_order_line`, confirm `sales`, `profit`, `discount`, `gross_list_value`,
   `discount_value` are **Fixed decimal number** (`Decimal` would reintroduce the
   float rounding that 03_cleaning.sql avoided).
3. `dim_date[date_key]` → **Date**. `fact_order_line[date_key]` → **Date**.
4. Nothing else. `Close & Apply`.

### 0.3 Relationships

`Modeling ▸ Manage relationships`. All are **many-to-one, single direction**, from
fact to dimension:

| From | To | Cardinality | Cross-filter |
|---|---|---|---|
| `fact_order_line[date_key]` | `dim_date[date_key]` | \* → 1 | Single |
| `fact_order_line[customer_key]` | `dim_customer[customer_key]` | \* → 1 | Single |
| `fact_order_line[product_key]` | `dim_product[product_key]` | \* → 1 | Single |
| `fact_order_line[geography_key]` | `dim_geography[geography_key]` | \* → 1 | Single |
| `fact_return[date_key]` | `dim_date[date_key]` | \* → 1 | Single |
| `fact_return[customer_key]` | `dim_customer[customer_key]` | \* → 1 | Single |
| `fact_return[geography_key]` | `dim_geography[geography_key]` | \* → 1 | Single |

**`fact_target` has no key columns.** Relate it on the text `region` to a region
dimension, or — simpler and what this build does — leave it disconnected and let the
`Target Attainment %` measure resolve region via `TREATAS`. If you prefer a
relationship: create `dim_region` (4 rows) from `dim_geography`, relate both
`fact_target[region]` and `dim_geography[region]` to it, and you get a slicer that
filters both facts. Either is defensible; the second is tidier and is what I would
do with another hour.

**Two rules to hold to, and the reason for each:**

- **No bidirectional cross-filtering anywhere.** Bidirectional filters on two facts
  sharing a dimension create ambiguous paths, and Power BI resolves ambiguity by
  picking one silently. If a visual needs filtering the "wrong" way, use
  `CROSSFILTER` inside that one measure — a local, visible, reviewable exception.
- **No relationship between `fact_order_line` and `fact_return`.** They are at
  different grains and joining them is the exact bug in Priya's email. They meet
  through the shared dimensions, and through the pre-computed `is_returned` flag.

### 0.4 Mark the date table — do not skip this

`dim_date` selected ▸ `Table tools ▸ Mark as date table ▸ date_key`.

Without it, `SAMEPERIODLASTYEAR` and `TOTALYTD` **return wrong numbers rather than
erroring**. Power BI falls back on auto-generated date hierarchies, one per date
column, and the YoY comparison quietly shifts. This is the single most common cause
of "my time intelligence looks slightly off".

Then `File ▸ Options ▸ Current file ▸ Data load ▸ untick Auto date/time`. It creates
a hidden date table per date column, bloating the model for no benefit once a real
calendar exists.

### 0.5 Hide, sort, categorise

**Hide from report view** (right-click ▸ Hide): every `*_key` column on every table,
plus `fact_order_line[src_row_id]`. Keys are join plumbing; a report author who drags
`customer_key` onto a visual gets a meaningless integer.

**Sort by column** (`Column tools ▸ Sort by column`):

| Column | Sort by |
|---|---|
| `dim_date[month_name]` | `month_no` |
| `dim_date[day_of_week]` | `day_of_week_no` |
| `dim_date[quarter_name]` | `quarter_no` |

Without this, months sort alphabetically: Apr, Aug, Dec, Feb… Everyone hits this once.

**Data categories** (`Column tools ▸ Data category`) — needed for the map:

| Column | Category |
|---|---|
| `dim_geography[country]` | Country/Region |
| `dim_geography[state]` | State or Province |
| `dim_geography[city]` | City |
| `dim_geography[postal_code]` | Postal Code |

**Format**: `sales`, `profit` → Currency, 0 dp. `discount` → Percentage, 0 dp.
`Margin %`, `Return Rate %` and every ratio measure → Percentage, 2 dp.

### 0.6 The measure table

`Home ▸ Enter data` ▸ one column, one blank row ▸ name the table `_Measures` ▸ Load.
Create the first measure on it, then delete the dummy column. The table stays and
becomes measures-only; Power BI floats it to the top of the field list.

Paste everything from [`measures.dax`](measures.dax), assigning each measure to the
display folder named in its comment (`Properties ▸ Display folder`). 42 measures in
9 folders. A flat list of 42 is unusable by anyone but its author.

### 0.7 The what-if parameters

`Modeling ▸ New parameter ▸ Numeric range`:

| Name | Min | Max | Increment | Default | Add slicer |
|---|---|---|---|---|---|
| `Discount Cap` | 0.05 | 0.60 | 0.05 | 0.30 | yes, Page 1 |
| `Survival Rate` | 0 | 1 | 0.05 | 0.75 | yes, Page 1 |

Power BI generates the calculated table and the `SELECTEDVALUE` measure. Format both
as Percentage.

### 0.8 Theme

`View ▸ Themes ▸ Browse for themes` ▸ [`theme.json`](theme.json).

Eight categorical colours in a fixed order, validated for colour-vision deficiency
(worst adjacent pair ΔE 9.1 against a ≥8 target). Conditional formatting for margin
uses the **blue↔red diverging pair with a grey midpoint**, not red↔green: red-green
is the most common CVD pair and a margin heatmap is exactly where a reader most needs
to distinguish the poles. Three of the eight sit below 3:1 contrast on the light
surface, so every chart using them ships visible data labels or a table view — that
is the documented relief, not an oversight.

---

## Phase 1 — Page 1 · Margin & Executive (105 min)

*Rebuilt around margin recovery because the change request moved it to the front.*

**Header band** (full width, 60px): title `Margin recovery — where profit went, and
what a discount cap is worth`; subtitle `Northwind Retail · FY2018–FY2021 · gross of
returns unless stated`; right-aligned card with `[Last Refresh]`.

**Slicer row** (below header, 40px): `dim_date[year]` (tile), `dim_geography[region]`
(dropdown), `dim_product[category]` (dropdown). Set `Format ▸ Edit interactions` so
slicers filter every visual on the page.

### Visual 1.1 — KPI row (6 cards, full width)

| Card | Measure | Reads |
|---|---|---|
| Revenue | `[Revenue]` | $218.6M |
| Profit | `[Profit]` | $47.3M |
| Margin % | `[Margin %]` + `[Margin Change (pp)]` as callout | 21.62% ▼ 2.49 pp |
| Discount % (weighted) | `[Discount % (weighted)]` | 12.18% |
| Profit at 50%+ discount | `[Profit at 50%+ Discount]` | −$2.11M |
| Return rate | `[Return Rate %]` | 8.19% |

Conditional-format the Margin card's font with `[KPI Colour Margin]`
(`Format ▸ Callout value ▸ Colour ▸ fx ▸ Field value`).

### Visual 1.2 — Discount-vs-margin curve  ← *the headline visual*

**Line chart.** X: `fact_order_line[discount]` binned to 5 points (`Right-click the
field ▸ New group ▸ Bin size 0.05`). Y: `[Margin %]`. Add a **constant line at 0**
(`Analytics ▸ Constant line ▸ 0`, red `#d03b3b`, label "break-even").

This one chart is the whole argument: margin falls monotonically with discount and
crosses zero between the 20–29% and 30–39% bands. `../sql/11_product_performance.sql`
DP-02 is the source; the bands and their margins are in
[`dax-vs-sql-gate.md`](dax-vs-sql-gate.md).

Add a second series by `dim_product[category]` **only if** you keep it to the three
categories — three series is inside the all-pairs colour limit, more is not.

### Visual 1.3 — Break-even threshold by sub-category

**Bar chart**, horizontal. Y: `dim_product[sub_category]`. X: a calculated column or
the imported `core.v_subcat_breakeven` view (easiest: add the view as an eighth
table). Sort ascending. Data labels on.

The reader's takeaway in one glance: Tables break even at 10%, Binders and Paper at
60%. **A single company-wide cap is the wrong instrument** — that is the
recommendation this visual carries.

### Visual 1.4 — The counterfactual

**Clustered column** with two columns: `[Margin Recovery (Upper)]` and
`[Margin Recovery (Lower)]`, plus a card for `[Break-even Survival Rate]` and the
two what-if slicers beside it.

Title it **"What a discount cap is worth — a range, not a number"** and put the
assumption in the subtitle: *"Upper = every affected order survives the cap. Lower =
every order containing a capped line is lost entirely. Price elasticity is not
observable in this data."*

At the default 30% cap the reader sees **+$3.49M / −$3.31M, break-even at 48.6%
survival**. Dragging the cap slicer is the demo that sells the whole project.

### Visual 1.5 — Revenue and profit trend

**Line chart**, X `dim_date[year_month]`, Y `[Revenue]` and `[Profit]`.

> **One axis only.** These two differ by ~5×, and the temptation is a secondary
> y-axis. Do not — a dual axis lets the designer choose where the lines cross, which
> is a decision the data should be making. If the shapes must be compared directly,
> use the indexed version from `10_ SP-03` (both rebased to 100) as a second chart.
> `[Margin %]` on its own small line chart underneath is the better answer, and is
> what makes the divergence obvious.

### Visual 1.6 — Profit bridge

**Waterfall.** Category `dim_date[year]`, Y `[Profit]`, breakdown by
`dim_product[category]`. Or, better and matching `10_ SP-04` exactly, a static
waterfall with three points: 2020 profit $14.74M → volume effect +$1.73M → margin
rate effect −$1.93M → 2021 profit $14.55M.

---

## Phase 2 — Page 2 · Product & Category (75 min)

### 2.1 Matrix with margin conditional formatting

Rows `dim_product[category]` ▸ `sub_category` (hierarchy). Values `[Revenue]`,
`[Profit]`, `[Margin %]`, `[Margin % vs Company]`, `[Discount % (weighted)]`,
`[Return Rate %]`.

Conditional-format `Margin %` background: `Format ▸ Cell elements ▸ Background colour
▸ fx ▸ Diverging`, min `#d03b3b`, centre `#f0efec` at 0, max `#2a78d6`. Tables goes
red at 3.62%; Paper and Binders go blue near 39%.

### 2.2 Pareto

**Line and clustered column.** Shared axis `dim_product[product_name]` sorted by
`[Revenue]` desc, column `[Revenue]`, line `[Cumulative Revenue %]`, constant line at
80%. Top N filter = 600 (the full 1,862 is unreadable and the curve is flat past 600).

Reads: **468 of 1,862 products — 25.1% of the catalogue — make 80% of revenue.**

### 2.3 Sales-vs-margin quadrant

**Scatter.** X `[Revenue]`, Y `[Margin %]`, size `[Units]`, legend
`dim_product[category]` (three series — inside the all-pairs colour limit), details
`dim_product[product_name]`. Add median constant lines on both axes so the quadrants
are drawn from the data, not from an invented threshold.

The lower-right quadrant is the action list: 647 products, 12.0% average discount
versus 10.3% elsewhere.

### 2.4 Chronic underperformers

**Table**: sub-category, `months below company margin` (out of 48), `months negative`,
average monthly margin. Source `11_ PP-07`.

Seven sub-categories are below the company margin in **48 of 48 months**. Say
"chronic", not "worst": an average would hide a line that is fine for ten months and
catastrophic for two, and those need different fixes.

### 2.5 Furniture hypothesis panel

Two cards and one small line chart answering Anand directly:
`Margin (all) 2018→2021: 27.17% → 18.78%` versus
`Margin excluding Furniture: 30.77% → 22.32%`.

Title: **"Furniture is a level problem, not the cause of the decline."** The slide is
−8.39 pp with Furniture and −8.45 pp without it.

---

## Phase 3 — Page 3 · Regional & Targets (75 min)

### 3.1 Filled map

Location `dim_geography[state]`, colour saturation `[Margin %]` using the diverging
palette, tooltip `[Revenue]`, `[Profit]`, `[Target Attainment %]`.

Maps need the data categories set in 0.5 or Power BI geocodes "Washington" as the
wrong thing.

### 3.2 Target vs actual

**Clustered bar**: `dim_geography[region]` × `[Revenue]` and `[Revenue Target]`, with
`[Target Attainment %]` as a data label. 2021 slicer default.

East 107.7 · South 107.3 · Central 96.3 · **West 93.7 (−$1.94M)**.

### 3.3 Data-quality panel (TA-03)

A text box plus a small table. This panel is not decoration — it is the answer to
"can these targets be shown to a board at all", and putting the caveat *on* the visual
is what stops someone screenshotting the bar chart without it:

> Targets were supplied as 17 rows using **10 different spellings** of 4 regions,
> with 3 rows recorded in thousands, 2 exact duplicates, and **no target at all for
> Central 2018**. Mapped through an explicit crosswalk (`core.region_map`) rather
> than a fuzzy match, so every mapping can be confirmed by the target owner. The
> missing Central 2018 target has been left missing rather than estimated.

### 3.4 The West panel  ← *the second real finding*

Three visuals answering RP-02 in the order a sceptical reader needs them:

1. **Bar** — margin by region, 2021: West 14.39% vs South 23.34%.
2. **Line** — margin **on full-price lines only** (`discount = 0`), by region, by
   year: West 33.34% → 24.70%; South 33.37% → 33.59%.
3. **Text**: *"West is not under-resourced on any measure the data can see — it has
   the highest revenue per customer ($2,249) and the most orders per customer (3.49).
   Its discount rate is within 0.4 points of every other region. The gap is on
   full-price business, where West lost 8.64 margin points in four years while South
   lost none. That is a pricing or cost-to-serve question, not a headcount one."*

---

## Phase 4 — Page 4 · Customer & Returns (60 min)

*Demoted by the change request. Built because it was already written; kept short.*

- Donut: repeat (72.4%) vs one-time customers.
- Column: RFM segments by customer count and revenue share, from `core.v_customer_rfm`.
- Card row: at-risk customers **9,468**, lifetime revenue at risk **$32.9M**, average
  **594 days** quiet.
- Bar: return rate by sub-category (Machines 17.32%, Tables 13.99%).
- **Waterfall**: gross revenue $218.6M → returns −$23.2M → net $195.4M.
- Line: return rate by month, with the flat trend visible. Subtitle:
  *"Return rate has not moved in four years — 8.12% in 2018, 8.20% in 2021."*
- **Attribution caveat, on the visual**: *"A return is recorded against a whole order.
  'Returns by category' therefore means the category lines that sat on a returned
  order, not the item sent back — the source cannot distinguish them."*

---

## Phase 5 — Interactivity (45 min)

| Feature | Where | How |
|---|---|---|
| **Drill-through** | new hidden page `Product detail` | `Drill through` field = `dim_product[product_name]`; put the product's trend, discount band table and return rate on it |
| **Tooltip page** | new page, size `Tooltip` | Page information ▸ Allow use as tooltip. Sparkline + margin + discount. Assign per visual under `Format ▸ Tooltip ▸ Report page` |
| **Reset bookmark** | all pages | `View ▸ Bookmarks ▸ Add` with slicers cleared; `Data` unticked → captures display only. Button ▸ Action ▸ Bookmark |
| **Sync slicers** | year, region | `View ▸ Sync slicers` ▸ tick all four pages for both |
| **Edit interactions** | Page 1 | Turn OFF cross-filtering from the KPI cards — clicking a card filtering the page is never what anyone wants |
| **Alt text** | every visual | `Format ▸ General ▸ Alt text`. One sentence saying what the visual shows and its headline |
| **Page navigation** | header of each page | Four buttons, `Action ▸ Page navigation` |

---

## Phase 6 — Security (45 min)

The change request says: *"can we make sure nobody outside Commercial can see
customer names?"*

### The thing worth knowing

**RLS filters rows. It cannot hide a column.** A `Restricted` role with a filter on
`dim_customer` removes customers from the model — which also removes their revenue,
so every total on every page changes for that user. That is not what Legal asked for.

Hiding a *column* from a *role* is **Object-Level Security**, and Power BI Desktop has
no UI for it. So this build does three things, and the README says which is which:

**1. OLS — the correct control (via Tabular Editor 2, free).**

```
Model ▸ Roles ▸ Restricted ▸ Table Permissions ▸ dim_customer
   customer_name ▸ Object Level Security ▸ None
```
Save back to the model. Members of `Restricted` cannot see, query or reference that
column; a visual using it errors rather than leaking. `customer_name_masked` stays
visible.

**2. A masked display column — the practical control, always on.**

`dim_customer[customer_name_masked]` was built in `05_dimensional_model.sql`:
`Claire Gute` + `CG-12520` → `C. G. (CG-12520)`. Every visual in the file uses it.
`customer_name` is hidden from report view. Anyone opening the `.pbix` — including a
recruiter — sees masked names, which is also why this is the version that ships.

**3. Genuine RLS, where it genuinely applies.**

`Modeling ▸ Manage roles`:

| Role | Table | DAX filter |
|---|---|---|
| `Commercial` | — | *(no filter — sees everything)* |
| `West Regional Manager` | `dim_geography` | `[region] = "West"` |
| `Regional Manager (dynamic)` | `dim_geography` | `[region] = LOOKUPVALUE(dim_user_region[region], dim_user_region[email], USERPRINCIPALNAME())` |

Test with `Modeling ▸ View as ▸ Role`. Under `West Regional Manager`, revenue must
read **$77,313,380.96** and the region slicer must show only West. If any other
region is still visible, the relationship from `fact_order_line` to `dim_geography`
is not filtering — check it is single-direction, many-to-one.

The dynamic role is the pattern used in production: one small mapping table of
email → region, so adding a manager is a data change rather than a model change. It
needs a `dim_user_region` table, which this file does not ship because there are no
real users; the row is here because "how would you scale that to 40 managers" is the
follow-up question.

---

## Phase 7 — The gate (45 min, never skip)

Before any of this is shown to anyone, build a scratch page and put every measure
next to its SQL number. Results and method: [`dax-vs-sql-gate.md`](dax-vs-sql-gate.md).

A mismatch at this gate is always a real bug, and almost always one of three:

1. a relationship pointing the wrong way, or bidirectional,
2. a measure aggregating at the wrong grain (`Orders` as `COUNTROWS` not
   `DISTINCTCOUNT`),
3. `dim_date` not marked as a date table, so time intelligence drifted.

Delete the scratch page when it passes. Keep the screenshot.
