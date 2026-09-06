# SEALED — e-commerce dataset key

**Do not open before Day 5's grading block.**

Built 2026-09-06 13:01  ·  build_seed `1011699666`

<details>
<summary><b>Open on Day 5</b></summary>

## Shape

- Order lines: **1,000,569** (clean 1,000,569 + injected)
- Orders: 338,034 · Customers: 110,000 · Products: 1,862
- Window: 2018-01-01 to 2021-12-31
- Gross sales (pre-defect): 219,458,332.48
- Gross profit (pre-defect): 47,422,446.94
- Returned orders: 27,682 (8.19%); returns file has 30,727 rows because ~11% are duplicated

## Planted business signals

| Signal | Detail |
|---|---|
| Discount creep | Mean discount rises 12.8% (2018) -> 14.7% (2019) -> 18.1% (2020) -> 21.2% (2021) |
| Discount hotspots | Tables +7.5%/yr, Bookcases +6.0%/yr, Machines +4.5%/yr |
| Margin cliff | Contribution margin crosses zero at: Tables 16%, Bookcases 19%, Machines 22%, Supplies 24%, Storage 34%, Chairs 36% |
| Region West | volume +23.5%/yr, margin -2.8%/yr |
| Region East | volume +11.5%/yr, margin -0.4%/yr |
| Region Central | volume +4.8%/yr, margin -1.1%/yr |
| Region South | volume +2.1%/yr, margin +0.2%/yr |
| Seasonality | peak months Sep/Nov/Dec (x1.52), trough Jan (x0.62) |
| Return hotspots | Machines x3.6, Tables x2.9, Bookcases x2.4, Appliances x2.1, Copiers x1.9, Phones x1.6 |
| Weak cohort | customers acquired 2020-04-01 to 2020-09-30 repeat at 55% of normal |

## Injected data-quality defects

| Defect | Description | Rate | Rows |
|---|---|---|---|
| `ship_before_order` | Ship Date earlier than Order Date | 0.250% | 2,501 |
| `dup_row_id` | Row ID reused across two different orders | 0.250% | 2,501 |
| `customer_id_two_names` | One Customer ID mapped to two different Customer Names | 0.150% | 34 |
| `thousands_separator` | Sales written with a thousands comma, e.g. '1,234.56' | 0.040% | 400 |
| `zero_sales_with_qty` | Sales = 0 while Quantity > 0 | 0.400% | 4,002 |
| `region_whitespace` | Region with leading/trailing whitespace | 0.080% | 800 |
| `region_case` | Region written in mixed case ('west', 'WEST') | 0.150% | 1,500 |

Not injected this build: `exact_duplicate_rows`, `shipmode_whitespace`, `negative_quantity`, `null_postal`, `discount_out_of_range`, `product_id_two_names`, `date_format_drift`, `trailing_space_category`, `future_order_date`

## Targets file defects

- Region spelled 4 ways per region (`West` / `west` / `West Region` / `W`)
- Header `Region ` has a trailing space
- ~30% of rows are in thousands, flagged only by a `Units` column
- 2 duplicated region-year rows
- 1 blank row
- 1 region-year deliberately missing

</details>
