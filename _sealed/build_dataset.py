"""
build_dataset.py  --  DO NOT READ THIS FILE BEFORE DAY 5.

Builds the e-commerce sprint dataset from the raw Superstore extract:

  1. Scales 9,994 order lines to ~1,000,000 across the same 2018-2021 window,
     preserving real products, geography and category structure.
  2. Plants a set of business signals you are meant to DISCOVER, not be told.
  3. Injects a randomly chosen subset of data-quality defects at random rates.
  4. Generates a deliberately messy regional targets file (second source).
  5. Writes _DATASET-KEY.md describing exactly what it planted.

Reading the source, or the key, before you have done the analysis turns the
project into a tutorial. Run it, then leave this folder alone.

    python _sealed/build_dataset.py

Outputs to 02-Datasets/Raw/ecommerce-scaled/
"""

from __future__ import annotations

import hashlib
import os
import random
import secrets
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

import numpy as np
import pandas as pd

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
ROOT = PROJECT.parent.parent                      # ...\PBI Dashboads
RAW = ROOT / "02-Datasets" / "Raw"
SRC_ORDERS = RAW / "tableau-superstore-orders-202609.csv"
OUT_DIR = RAW / "ecommerce-scaled"

TARGET_LINES = 1_000_000
N_CUSTOMERS = 110_000
WINDOW_START = date(2018, 1, 1)
WINDOW_END = date(2021, 12, 31)

# ---------------------------------------------------------------------------
# Planted signals  (documented in _DATASET-KEY.md, hidden from the analyst)
# ---------------------------------------------------------------------------

# Discount at which contribution margin crosses zero, per sub-category.
# Low value == margin dies fast under discounting == the story to find.
BREAKEVEN_DISCOUNT = {
    "Tables": 0.16,
    "Bookcases": 0.19,
    "Machines": 0.22,
    "Supplies": 0.24,
    "Storage": 0.34,
    "Chairs": 0.36,
    "Appliances": 0.38,
    "Phones": 0.40,
    "Art": 0.46,
    "Accessories": 0.48,
    "Furnishings": 0.50,
    "Copiers": 0.55,
    "Fasteners": 0.58,
    "Envelopes": 0.60,
    "Labels": 0.62,
    "Binders": 0.64,
    "Paper": 0.66,
}

# Mean discount by year -- the "discount creep" Finance suspects.
DISCOUNT_DRIFT = {2018: 0.128, 2019: 0.147, 2020: 0.181, 2021: 0.212}

# Sub-categories where discounting escalates faster than the fleet.
DISCOUNT_HOTSPOTS = {"Tables": 0.075, "Bookcases": 0.060, "Machines": 0.045}

# Region volume growth (index, 2018 = 1.0) and margin decay per year.
REGION_GROWTH = {
    "West":    {"growth": 0.235, "margin_decay": 0.028},   # loud, growing, quietly bleeding
    "East":    {"growth": 0.115, "margin_decay": 0.004},
    "Central": {"growth": 0.048, "margin_decay": 0.011},
    "South":   {"growth": 0.021, "margin_decay": -0.002},  # flat volume, improving margin
}

MONTH_SEASONALITY = {
    1: 0.62, 2: 0.71, 3: 1.06, 4: 0.88, 5: 0.97, 6: 1.09,
    7: 0.86, 8: 1.02, 9: 1.44, 10: 1.11, 11: 1.52, 12: 1.47,
}

YEAR_VOLUME = {2018: 0.79, 2019: 0.93, 2020: 1.08, 2021: 1.20}

# Return propensity multipliers -- some top sellers also return heavily.
RETURN_RATE_BASE = 0.048
RETURN_HOTSPOTS = {
    "Machines": 3.6, "Tables": 2.9, "Bookcases": 2.4,
    "Appliances": 2.1, "Copiers": 1.9, "Phones": 1.6,
}

# Cohort quality: customers first seen in this window repeat noticeably less.
WEAK_COHORT = (date(2020, 4, 1), date(2020, 9, 30))
WEAK_COHORT_PENALTY = 0.55

# ---------------------------------------------------------------------------
# Data-quality defect menu -- a random subset is applied each build
# ---------------------------------------------------------------------------

DEFECT_MENU = [
    ("exact_duplicate_rows",      "Whole rows duplicated verbatim"),
    ("dup_row_id",                "Row ID reused across two different orders"),
    ("region_case",               "Region written in mixed case ('west', 'WEST')"),
    ("region_whitespace",         "Region with leading/trailing whitespace"),
    ("shipmode_whitespace",       "Ship Mode with trailing whitespace"),
    ("ship_before_order",         "Ship Date earlier than Order Date"),
    ("negative_quantity",         "Quantity negative"),
    ("zero_sales_with_qty",       "Sales = 0 while Quantity > 0"),
    ("null_postal",               "Postal Code blank"),
    ("discount_out_of_range",     "Discount > 1.0 or negative"),
    ("product_id_two_names",      "One Product ID mapped to two different Product Names"),
    ("customer_id_two_names",     "One Customer ID mapped to two different Customer Names"),
    ("date_format_drift",         "A slice of Order Date written as DD-MM-YYYY instead of ISO"),
    ("thousands_separator",       "Sales written with a thousands comma, e.g. '1,234.56'"),
    ("trailing_space_category",   "Category with a trailing space"),
    ("future_order_date",         "Order Date beyond the dataset window"),
]

N_DEFECTS = 7


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def log(msg: str) -> None:
    print(f"  {msg}", flush=True)


def build_name_pools(base: pd.DataFrame) -> tuple[list[str], list[str]]:
    firsts, lasts = set(), set()
    for name in base["Customer Name"].dropna().unique():
        parts = str(name).split()
        if len(parts) >= 2:
            firsts.add(parts[0])
            lasts.add(parts[-1])
    return sorted(firsts), sorted(lasts)


def main() -> None:
    if not SRC_ORDERS.exists():
        sys.exit(f"ERROR: source not found: {SRC_ORDERS}")

    build_seed = secrets.randbelow(2**31)
    rng = np.random.default_rng(build_seed)
    pyrandom = random.Random(build_seed)

    print(f"\nE-commerce dataset builder   build_seed={build_seed}")
    print("=" * 64)

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # -- 1. base reference data --------------------------------------------
    log("reading base Superstore extract...")
    base = pd.read_csv(SRC_ORDERS)
    base.columns = [c.strip() for c in base.columns]

    products = (
        base[["Product ID", "Category", "Sub-Category", "Product Name"]]
        .drop_duplicates(subset=["Product ID"])
        .reset_index(drop=True)
    )
    # unit price implied by undiscounted lines
    undisc = base[(base["Discount"] == 0) & (base["Quantity"] > 0)].copy()
    undisc["unit_price"] = undisc["Sales"] / undisc["Quantity"]
    price = undisc.groupby("Product ID")["unit_price"].median()
    sub_price = undisc.groupby("Sub-Category")["unit_price"].median()
    products["unit_price"] = products["Product ID"].map(price)
    products["unit_price"] = products["unit_price"].fillna(
        products["Sub-Category"].map(sub_price)
    ).fillna(60.0)

    geo = (
        base[["Country/Region", "City", "State", "Postal Code", "Region"]]
        .drop_duplicates()
        .reset_index(drop=True)
    )
    geo_by_region = {r: g.reset_index(drop=True) for r, g in geo.groupby("Region")}

    log(f"  {len(products):,} products, {len(geo):,} locations, "
        f"{len(geo_by_region)} regions")

    # -- 2. customers -------------------------------------------------------
    log(f"generating {N_CUSTOMERS:,} customers...")
    firsts, lasts = build_name_pools(base)
    span_days = (WINDOW_END - WINDOW_START).days

    # acquisition skewed toward later years (business is growing)
    acq_offset = (rng.beta(1.6, 2.1, N_CUSTOMERS) * span_days).astype(int)
    first_date = np.array([WINDOW_START + timedelta(days=int(d)) for d in acq_offset])

    region_names = list(REGION_GROWTH.keys())
    region_p = np.array([0.32, 0.28, 0.22, 0.18])
    cust_region = rng.choice(region_names, N_CUSTOMERS, p=region_p)
    segments = rng.choice(
        ["Consumer", "Corporate", "Home Office"], N_CUSTOMERS, p=[0.52, 0.30, 0.18]
    )

    # Order RATE (orders per year) x tenure, not a fixed order count. Modelling
    # it as a rate is what makes aggregate volume grow through the window: each
    # cohort keeps buying after it arrives, so later years carry the sum of all
    # cohorts acquired so far. A fixed count with exponential gaps instead makes
    # every customer go quiet ~a year after acquisition, and total revenue humps
    # in the middle of the window and then collapses.
    rate = rng.gamma(2.0, 0.90, N_CUSTOMERS)                    # orders per year
    in_weak = np.array([WEAK_COHORT[0] <= d <= WEAK_COHORT[1] for d in first_date])
    rate = np.where(in_weak, rate * WEAK_COHORT_PENALTY, rate)
    tenure_days = np.array([(WINDOW_END - d).days for d in first_date])
    tenure_years = tenure_days / 365.25
    n_orders = 1 + rng.poisson(np.clip(rate * tenure_years, 0.0, None))

    cust_ids, seen = [], set()
    for i in range(N_CUSTOMERS):
        fn = pyrandom.choice(firsts)
        ln = pyrandom.choice(lasts)
        base_id = f"{fn[0]}{ln[0]}-{pyrandom.randint(10000, 99999)}".upper()
        while base_id in seen:
            base_id = f"{fn[0]}{ln[0]}-{pyrandom.randint(10000, 99999)}".upper()
        seen.add(base_id)
        cust_ids.append((base_id, f"{fn} {ln}"))

    customers = pd.DataFrame({
        "Customer ID": [c[0] for c in cust_ids],
        "Customer Name": [c[1] for c in cust_ids],
        "Segment": segments,
        "Region": cust_region,
        "first_date": first_date,
        "n_orders": n_orders,
        "tenure_days": tenure_days,
        "acq_day": acq_offset,
    })
    log(f"  mean orders/customer before seasonal thinning: {n_orders.mean():.2f}")

    # -- 3. orders ----------------------------------------------------------
    log("generating order headers...")
    cust_idx = np.repeat(np.arange(N_CUSTOMERS), customers["n_orders"].to_numpy())
    n_raw = len(cust_idx)

    # first order sits exactly on the acquisition date; the rest land uniformly
    # across the customer's remaining tenure, so they stay active to the end
    is_first = np.r_[True, cust_idx[1:] != cust_idx[:-1]]
    acq = customers["acq_day"].to_numpy()[cust_idx]
    ten = customers["tenure_days"].to_numpy()[cust_idx]
    order_day = np.where(is_first, acq, acq + rng.random(n_raw) * ten).astype(int)

    keep = (order_day >= 0) & (order_day <= span_days)
    cust_idx, order_day, is_first = cust_idx[keep], order_day[keep], is_first[keep]

    srt = np.lexsort((order_day, cust_idx))
    cust_idx, order_day, is_first = cust_idx[srt], order_day[srt], is_first[srt]

    order_dates = np.array([WINDOW_START + timedelta(days=int(d)) for d in order_day])
    years = np.array([d.year for d in order_dates])
    months = np.array([d.month for d in order_dates])

    # thin by seasonality x year volume x region growth -> creates trend + season
    w_month = np.array([MONTH_SEASONALITY[m] for m in months])
    w_year = np.array([YEAR_VOLUME[y] for y in years])
    reg = customers["Region"].to_numpy()[cust_idx]
    yr_ix = years - 2018
    w_region = np.array([1.0 + REGION_GROWTH[r]["growth"] * y for r, y in zip(reg, yr_ix)])

    weight = w_month * w_year * w_region
    weight = np.clip(weight / np.quantile(weight, 0.97), 0, 1.0)
    accept = rng.random(len(weight)) < weight
    # never thin a customer's first order, or the acquisition cohort they
    # belong to becomes an artefact of the sampler rather than of behaviour
    accept[is_first] = True
    cust_idx, order_dates, years, months, reg = (
        cust_idx[accept], order_dates[accept], years[accept],
        months[accept], reg[accept],
    )

    n_orders_final = len(cust_idx)
    lines_per_order = np.maximum(1, rng.poisson(2.9, n_orders_final))
    scale = TARGET_LINES / lines_per_order.sum()
    if scale < 1.0:
        keep2 = rng.random(n_orders_final) < scale
        cust_idx, order_dates, years, months, reg, lines_per_order = (
            cust_idx[keep2], order_dates[keep2], years[keep2],
            months[keep2], reg[keep2], lines_per_order[keep2],
        )
        n_orders_final = len(cust_idx)

    log(f"  {n_orders_final:,} orders -> {lines_per_order.sum():,} lines")

    # strictly unique: the running index guarantees no two orders collide,
    # which matters because a collision would silently merge two orders.
    order_ids = np.array([
        f"{'CA' if r < 0.93 else 'US'}-{y}-{i:07d}"
        for i, (y, r) in enumerate(zip(years, rng.random(n_orders_final)))
    ])

    ship_lag = rng.choice([1, 2, 3, 4, 5, 6, 7], n_orders_final,
                          p=[0.06, 0.13, 0.22, 0.24, 0.18, 0.11, 0.06])
    ship_mode = rng.choice(
        ["Standard Class", "Second Class", "First Class", "Same Day"],
        n_orders_final, p=[0.60, 0.19, 0.15, 0.06],
    )

    # -- 4. explode to lines and price them --------------------------------
    log("exploding to line grain and pricing...")
    line_order_ix = np.repeat(np.arange(n_orders_final), lines_per_order)
    n_lines = len(line_order_ix)

    prod_ix = rng.integers(0, len(products), n_lines)
    p_sub = products["Sub-Category"].to_numpy()[prod_ix]
    p_price = products["unit_price"].to_numpy()[prod_ix]

    qty = rng.choice([1, 2, 3, 4, 5, 6, 7, 8, 9],
                     n_lines, p=[.19, .24, .18, .13, .10, .07, .04, .03, .02])

    line_year = years[line_order_ix]
    base_disc = np.array([DISCOUNT_DRIFT[y] for y in line_year])
    hotspot = np.array([DISCOUNT_HOTSPOTS.get(s, 0.0) for s in p_sub])
    disc_mean = base_disc + hotspot * (line_year - 2018)

    raw_disc = rng.gamma(1.5, disc_mean / 1.5)
    discount = np.where(rng.random(n_lines) < 0.42, 0.0, raw_disc)
    discount = np.round(np.clip(discount, 0.0, 0.85) * 20) / 20  # to nearest 0.05

    sales = np.round(p_price * qty * (1.0 - discount), 4)

    m0 = np.array([
        BREAKEVEN_DISCOUNT.get(s, 0.45) for s in p_sub
    ])
    # margin rate at zero discount, calibrated so profit crosses 0 at breakeven
    base_margin = np.array([
        {"Tables": .195, "Bookcases": .220, "Storage": .245, "Chairs": .250,
         "Supplies": .270, "Phones": .280, "Appliances": .280, "Art": .290,
         "Accessories": .330, "Furnishings": .340, "Fasteners": .450,
         "Copiers": .455, "Machines": .460, "Envelopes": .470,
         "Labels": .470, "Binders": .480, "Paper": .480}.get(s, .30)
        for s in p_sub
    ])
    alpha = base_margin / m0
    line_reg = reg[line_order_ix]
    decay = np.array([REGION_GROWTH[r]["margin_decay"] for r in line_reg])
    margin_rate = base_margin - alpha * discount - decay * (line_year - 2018)
    margin_rate += rng.normal(0, 0.035, n_lines)
    profit = np.round(sales * margin_rate, 4)

    # -- 5. assemble --------------------------------------------------------
    log("assembling frame...")
    geo_df = pd.DataFrame(index=np.arange(n_orders_final),
                          columns=geo.columns, dtype=object)
    for r, g in geo_by_region.items():
        mask = reg == r
        pick = rng.integers(0, len(g), mask.sum())
        geo_df.loc[mask, :] = g.iloc[pick].to_numpy()
    geo_df = geo_df.reset_index(drop=True)

    orders_df = pd.DataFrame({
        "Order ID": order_ids,
        "Order Date": [d.isoformat() for d in order_dates],
        "Ship Date": [(d + timedelta(days=int(l))).isoformat()
                      for d, l in zip(order_dates, ship_lag)],
        "Ship Mode": ship_mode,
        "Customer ID": customers["Customer ID"].to_numpy()[cust_idx],
        "Customer Name": customers["Customer Name"].to_numpy()[cust_idx],
        "Segment": customers["Segment"].to_numpy()[cust_idx],
        "Country/Region": geo_df["Country/Region"].to_numpy(),
        "City": geo_df["City"].to_numpy(),
        "State": geo_df["State"].to_numpy(),
        "Postal Code": geo_df["Postal Code"].to_numpy(),
        "Region": geo_df["Region"].to_numpy(),
    })

    df = orders_df.iloc[line_order_ix].reset_index(drop=True)
    df.insert(0, "Row ID", np.arange(1, n_lines + 1))
    df["Product ID"] = products["Product ID"].to_numpy()[prod_ix]
    df["Category"] = products["Category"].to_numpy()[prod_ix]
    df["Sub-Category"] = p_sub
    df["Product Name"] = products["Product Name"].to_numpy()[prod_ix]
    df["Sales"] = sales
    df["Quantity"] = qty
    df["Discount"] = discount
    df["Profit"] = profit

    df = df[[
        "Row ID", "Order ID", "Order Date", "Ship Date", "Ship Mode",
        "Customer ID", "Customer Name", "Segment", "Country/Region", "City",
        "State", "Postal Code", "Region", "Product ID", "Category",
        "Sub-Category", "Product Name", "Sales", "Quantity", "Discount", "Profit",
    ]]

    clean_rows = len(df)
    clean_sales = float(df["Sales"].sum())
    clean_profit = float(df["Profit"].sum())
    log(f"  clean: {clean_rows:,} rows, sales {clean_sales:,.2f}, "
        f"profit {clean_profit:,.2f}")

    # -- 6. returns ---------------------------------------------------------
    log("generating returns...")
    ord_sub = pd.DataFrame({
        "oid": order_ids[line_order_ix],
        "m": [RETURN_HOTSPOTS.get(s, 1.0) for s in p_sub],
    })
    mult = ord_sub.groupby("oid")["m"].max()
    p_ret = np.clip(RETURN_RATE_BASE * mult.to_numpy(), 0, 0.6)
    returned = mult.index.to_numpy()[rng.random(len(p_ret)) < p_ret]
    ret_df = pd.DataFrame({"Returned": "Yes", "Order ID": returned})
    # preserve the real Superstore quirk: the returns sheet has duplicate rows
    dupes = ret_df.sample(frac=0.11, random_state=build_seed % 2**31)
    ret_df = pd.concat([ret_df, dupes]).sample(frac=1.0, random_state=7)
    log(f"  {len(returned):,} returned orders "
        f"({len(returned)/len(mult)*100:.1f}%), {len(ret_df):,} rows in file")

    # -- 7. defect injection ------------------------------------------------
    log(f"injecting {N_DEFECTS} of {len(DEFECT_MENU)} possible defects...")
    chosen = pyrandom.sample(DEFECT_MENU, N_DEFECTS)
    # date-mutating defects must run last, or a later defect that parses
    # Order Date will trip over the format drift this one introduces.
    _LAST = {"date_format_drift", "future_order_date"}
    chosen.sort(key=lambda c: c[0] in _LAST)
    applied = []

    for key, desc in chosen:
        rate = pyrandom.choice([0.0004, 0.0008, 0.0015, 0.0025, 0.004, 0.006])
        n = max(1, int(len(df) * rate))
        idx = rng.choice(len(df), n, replace=False)

        if key == "exact_duplicate_rows":
            df = pd.concat([df, df.iloc[idx]], ignore_index=True)
        elif key == "dup_row_id":
            df.loc[idx, "Row ID"] = df["Row ID"].iloc[0]
        elif key == "region_case":
            df.loc[idx, "Region"] = df.loc[idx, "Region"].str.lower()
        elif key == "region_whitespace":
            df.loc[idx, "Region"] = " " + df.loc[idx, "Region"].astype(str) + " "
        elif key == "shipmode_whitespace":
            df.loc[idx, "Ship Mode"] = df.loc[idx, "Ship Mode"].astype(str) + " "
        elif key == "ship_before_order":
            df.loc[idx, "Ship Date"] = (
                pd.to_datetime(df.loc[idx, "Order Date"]) - pd.Timedelta(days=3)
            ).dt.strftime("%Y-%m-%d")
        elif key == "negative_quantity":
            df.loc[idx, "Quantity"] = -df.loc[idx, "Quantity"].abs()
        elif key == "zero_sales_with_qty":
            df.loc[idx, "Sales"] = 0.0
        elif key == "null_postal":
            df.loc[idx, "Postal Code"] = ""
        elif key == "discount_out_of_range":
            half = idx[: len(idx) // 2]
            df.loc[half, "Discount"] = 1.35
            df.loc[idx[len(idx) // 2:], "Discount"] = -0.15
        elif key == "product_id_two_names":
            pid = df["Product ID"].iloc[idx[0]]
            hit = df.index[df["Product ID"] == pid][: max(1, n // 4)]
            df.loc[hit, "Product Name"] = (
                df.loc[hit, "Product Name"].astype(str) + " (Refresh)"
            )
            n = len(hit)
        elif key == "customer_id_two_names":
            cid = df["Customer ID"].iloc[idx[0]]
            hit = df.index[df["Customer ID"] == cid][: max(1, n // 4)]
            df.loc[hit, "Customer Name"] = (
                df.loc[hit, "Customer Name"].astype(str).str.split().str[0] + " (dup)"
            )
            n = len(hit)
        elif key == "date_format_drift":
            df.loc[idx, "Order Date"] = pd.to_datetime(
                df.loc[idx, "Order Date"]
            ).dt.strftime("%d-%m-%Y")
        elif key == "thousands_separator":
            df["Sales"] = df["Sales"].astype(object)
            df.loc[idx, "Sales"] = df.loc[idx, "Sales"].map(lambda v: f"{float(v):,.4f}")
        elif key == "trailing_space_category":
            df.loc[idx, "Category"] = df.loc[idx, "Category"].astype(str) + " "
        elif key == "future_order_date":
            df.loc[idx, "Order Date"] = "2026-07-14"

        applied.append((key, desc, rate, n))
        log(f"    {key:26s} rate={rate:.4%}  rows={n:,}")

    df = df.sample(frac=1.0, random_state=build_seed % 2**31).reset_index(drop=True)

    # -- 8. targets file (deliberately messy second source) -----------------
    log("generating regional targets (messy on purpose)...")
    actual = (
        pd.DataFrame({"Region": reg[line_order_ix], "Year": line_year, "Sales": sales})
        .groupby(["Region", "Year"])["Sales"].sum().reset_index()
    )
    rows = []
    spellings = {
        "West": ["West", "west", "West Region", "W"],
        "East": ["East", "EAST", "East Region", "E"],
        "Central": ["Central", "central", "Central Region", "C"],
        "South": ["South", "South Region", "Sth", "south"],
    }
    for _, r in actual.iterrows():
        miss = pyrandom.uniform(-0.14, 0.19)
        tgt = float(r["Sales"]) * (1.0 + miss)
        label = pyrandom.choice(spellings[r["Region"]])
        if pyrandom.random() < 0.30:                       # some rows in thousands
            rows.append({"Region ": label, "Year": int(r["Year"]),
                         "Revenue Target": round(tgt / 1000, 2), "Units": "000s",
                         "Owner": pyrandom.choice(["Bhavna", "A. Mehta", ""])})
        else:
            rows.append({"Region ": label, "Year": int(r["Year"]),
                         "Revenue Target": round(tgt, 2), "Units": "",
                         "Owner": pyrandom.choice(["Bhavna", "A. Mehta", ""])})
    tgt_df = pd.DataFrame(rows)
    tgt_df = pd.concat([tgt_df, tgt_df.sample(2, random_state=3)], ignore_index=True)
    blank = pd.DataFrame([{c: "" for c in tgt_df.columns}])
    tgt_df = pd.concat([tgt_df.iloc[:5], blank, tgt_df.iloc[5:]], ignore_index=True)
    drop_ix = tgt_df.index[(tgt_df["Year"] == 2018)][:1]
    tgt_df = tgt_df.drop(drop_ix).reset_index(drop=True)

    # -- 9. write -----------------------------------------------------------
    log("writing files...")
    o_path = OUT_DIR / "orders.csv"
    r_path = OUT_DIR / "returns.csv"
    t_path = OUT_DIR / "targets.csv"
    df.to_csv(o_path, index=False, encoding="utf-8")
    ret_df.to_csv(r_path, index=False, encoding="utf-8")
    tgt_df.to_csv(t_path, index=False, encoding="utf-8")

    sizes = {p.name: p.stat().st_size / 1e6 for p in (o_path, r_path, t_path)}
    for k, v in sizes.items():
        log(f"  {k:14s} {v:8.1f} MB")

    # -- 10. sealed key -----------------------------------------------------
    key = HERE / "_DATASET-KEY.md"
    with open(key, "w", encoding="utf-8") as f:
        f.write("# SEALED — e-commerce dataset key\n\n")
        f.write("**Do not open before Day 5's grading block.**\n\n")
        f.write(f"Built {datetime.now():%Y-%m-%d %H:%M}  ·  build_seed `{build_seed}`\n\n")
        f.write("<details>\n<summary><b>Open on Day 5</b></summary>\n\n")
        f.write("## Shape\n\n")
        f.write(f"- Order lines: **{len(df):,}** (clean {clean_rows:,} + injected)\n")
        f.write(f"- Orders: {n_orders_final:,} · Customers: {N_CUSTOMERS:,} · "
                f"Products: {len(products):,}\n")
        f.write(f"- Window: {WINDOW_START} to {WINDOW_END}\n")
        f.write(f"- Gross sales (pre-defect): {clean_sales:,.2f}\n")
        f.write(f"- Gross profit (pre-defect): {clean_profit:,.2f}\n")
        f.write(f"- Returned orders: {len(returned):,} "
                f"({len(returned)/len(mult)*100:.2f}%); returns file has "
                f"{len(ret_df):,} rows because ~11% are duplicated\n\n")
        f.write("## Planted business signals\n\n")
        f.write("| Signal | Detail |\n|---|---|\n")
        f.write("| Discount creep | Mean discount rises "
                + " -> ".join(f"{v:.1%} ({k})" for k, v in DISCOUNT_DRIFT.items())
                + " |\n")
        f.write("| Discount hotspots | "
                + ", ".join(f"{k} +{v:.1%}/yr" for k, v in DISCOUNT_HOTSPOTS.items())
                + " |\n")
        f.write("| Margin cliff | Contribution margin crosses zero at: "
                + ", ".join(f"{k} {v:.0%}" for k, v in
                            sorted(BREAKEVEN_DISCOUNT.items(), key=lambda x: x[1])[:6])
                + " |\n")
        for r, cfg in REGION_GROWTH.items():
            f.write(f"| Region {r} | volume +{cfg['growth']:.1%}/yr, "
                    f"margin {-cfg['margin_decay']:+.1%}/yr |\n")
        f.write(f"| Seasonality | peak months Sep/Nov/Dec "
                f"(x{MONTH_SEASONALITY[11]:.2f}), trough Jan "
                f"(x{MONTH_SEASONALITY[1]:.2f}) |\n")
        f.write(f"| Return hotspots | "
                + ", ".join(f"{k} x{v}" for k, v in RETURN_HOTSPOTS.items()) + " |\n")
        f.write(f"| Weak cohort | customers acquired "
                f"{WEAK_COHORT[0]} to {WEAK_COHORT[1]} repeat at "
                f"{WEAK_COHORT_PENALTY:.0%} of normal |\n\n")
        f.write("## Injected data-quality defects\n\n")
        f.write("| Defect | Description | Rate | Rows |\n|---|---|---|---|\n")
        for k, d, rate, n in applied:
            f.write(f"| `{k}` | {d} | {rate:.3%} | {n:,} |\n")
        f.write(f"\nNot injected this build: "
                + ", ".join(f"`{k}`" for k, _ in DEFECT_MENU
                            if k not in {a[0] for a in applied}) + "\n\n")
        f.write("## Targets file defects\n\n")
        f.write("- Region spelled 4 ways per region (`West` / `west` / `West Region` / `W`)\n")
        f.write("- Header `Region ` has a trailing space\n")
        f.write("- ~30% of rows are in thousands, flagged only by a `Units` column\n")
        f.write("- 2 duplicated region-year rows\n")
        f.write("- 1 blank row\n")
        f.write("- 1 region-year deliberately missing\n\n")
        f.write("</details>\n")

    print("=" * 64)
    print(f"Done. Data -> {OUT_DIR}")
    print(f"Key  -> {key}  (SEALED — do not open until Day 4)\n")


if __name__ == "__main__":
    main()
