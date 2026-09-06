# SEALED — open at the start of Day 3, not before

This is the requirements change. Every real project has one. Opening it early removes the only
chance you get to practise re-planning under pressure in private.

Day 3 begins with a 20-minute block that says "open this file." Wait for it.

---

<details>
<summary><b>Open on Day 3 — click to expand</b></summary>

## The email

```
From:    Priya Raghavan <priya.r@northwind-retail.example>
To:      You
Subject: Change of plan - sorry
Date:    Wednesday, 08:47

Sorry to do this mid-flight.

Board meeting moved up to Friday morning, and the agenda changed. The CFO has
put "margin recovery" on it as a standing item, so Ritu's discounting question
is now the headline, not a footnote. She wants a specific number: what would we
have earned last year if we had capped discounts, and what would it have cost us
in lost orders.

Two consequences:

1. Please make the discount/margin analysis the FIRST thing I see when I open
   this. Not buried on a product page.

2. The customer retention piece - cohorts, RFM, all of that - I know you've
   probably started it, but it's not going in this deck. Park it. If it's cheap
   to leave in as a page I won't complain, but don't spend another hour on it.

Also Bhavna finally sent the target sheet. Attached. Fair warning, it's been
maintained by three different people and it shows. Anand wants target vs actual
by region in there if you can manage it.

One more thing and then I'll leave you alone: can we make sure nobody outside
Commercial can see customer names? Legal flagged it.

Priya
```

---

## What this actually costs you, and what to do

This is the exercise. Work through it in this order — **do not just start editing visuals.**

### 1. Re-scope before you re-build (15 min, on paper)

Write down, in `analysis/learning-log.md`:

- Which of your questions are now **promoted** (discount/margin, target vs actual, anything
  Finance-facing)
- Which are **demoted** (cohort retention, RFM, deep customer segmentation)
- Which are **new** and were not in your register at all
- What you will **cut** to make room, and what that costs

That written trade-off is the artefact. In a real job you send it back to the stakeholder as
"here is what I am dropping to do this" — and that email is what protects you when someone later
asks why retention was not covered.

### 2. The four concrete changes

| # | Change | Where | Rough cost |
|---|---|---|---|
| 1 | Promote discount/margin to Page 1 | Rebuild P1 around margin recovery; move the general KPI row down | 45 min |
| 2 | Answer the counterfactual: revenue and profit under a discount cap | New SQL query + a what-if parameter in Power BI | 60 min |
| 3 | Target vs actual by region | You already loaded `targets` on Day 1 — now it earns its place on a page | 30 min |
| 4 | Hide customer names outside Commercial | Row-level security, or an obfuscated display name | 30 min |

Total ~2h 45m of new work, against roughly 2h freed by parking the customer deep-dive. **You are
still net negative.** That is the normal outcome of a change request, and the correct response is
to cut something visible and say so — not to silently work longer.

### 3. The counterfactual is the interesting one

"What would we have earned if we had capped discounts at 20%?" is genuinely harder than it looks,
and getting the reasoning right matters more than the number.

The naive answer: recompute profit for every line with `discount > 0.20` as though it had been
`0.20`, and sum the difference. That is a fine first pass and you should produce it.

Then state the assumption you just made, because someone will attack it: **you assumed every one
of those orders would still have happened at the lower discount.** That is certainly false. Some
of them only converted because of the discount.

So bound it instead of pretending to a point estimate:

- **Upper bound** — all orders survive the cap. Full margin recovery. (The naive number.)
- **Lower bound** — every order that needed a discount above the cap is lost entirely, taking its
  revenue *and* its margin contribution with it.
- **Your recommendation sits between them**, and you say which assumption drives it.

> This is the single most interview-valuable thing in the whole e-commerce project. "I gave a
> range, not a point estimate, because I could not observe price elasticity in this data" is a
> senior-sounding sentence, and it is *true*.

### 4. Row-level security (30 min, and it is a real skill)

Power BI: **Modeling -> Manage roles**. Create a role `Commercial` with no filter, and a role
`Restricted` with a DAX filter on `dim_customer`. Test both with **View as -> Role**.

For the simple version, add a display column to `dim_customer` that masks the name, and use that
on visuals — e.g. `Claire Gute` becomes `C. G. (CG-12520)`. Note in the README which approach you
chose and why. RLS is the more correct answer; masking is the more practical one for a portfolio
file other people will open.

### 5. What NOT to do

- Do not delete the cohort/RFM work. Park it on a hidden page. Priya said "if it's cheap to leave
  in I won't complain" — and it stays in *your* portfolio write-up as work you did.
- Do not skip the Day 3 DAX-vs-SQL gate to make time. The gate is what stops you presenting a
  wrong number on the thing that just became the headline.
- Do not quietly absorb the overrun. Write the trade-off down.

</details>
