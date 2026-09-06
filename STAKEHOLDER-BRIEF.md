# Stakeholder brief — this is your actual input

> **This file replaces the pre-written question list.** Deriving questions from a vague ask is
> the single most valuable analyst skill, and it is the one thing a pre-filled register cannot
> teach you. Everything below is what you would really receive.

---

## The email

```
From:    Priya Raghavan <priya.r@northwind-retail.example>
To:      You
Cc:      Anand Mehta (Sales), Ritu Kapoor (Finance)
Subject: FW: Re: FW: numbers for the board deck — need help
Date:    Monday, 09:14

Hi,

Anand forwarded me your name — apparently you're the person who can actually
pull this stuff out of the system now.

Quick context. We've grown revenue every year for four years and the board is
happy, but Ritu ran some numbers for the annual review last week and profit
hasn't moved anything like as much. She thinks it's discounting. Anand thinks
it's the furniture line dragging. I honestly don't know, and that's the problem
- we're all guessing from different spreadsheets.

What I need before the board meeting is a proper view. Something I can open and
actually navigate rather than another 40-slide deck. Ideally covering:

  - how we're actually doing, month to month, versus last year
  - which products and categories are making us money and which aren't
  - who our good customers are, and whether we're keeping them
  - how the regions compare (West has been loud about being under-resourced)
  - and returns - Ritu keeps saying returns are eating us alive but nobody has
    ever put a number on it

More important than any of that: I need to walk out of the board meeting with
two or three things we're actually going to DO. Not "insights". Decisions.
With numbers attached, because someone will ask "how much" and "how do you know"
and I need to have an answer.

One thing to be careful of - the last person who looked at this told the board
our best region was Central, and it turned out they'd counted returned orders as
sales. That was embarrassing. So whatever you show me, I need to know you can
prove it.

Timeline is tight. Can you turn something around this week?

Priya
Head of Commercial

---------- Forwarded message ----------
From: Ritu Kapoor (Finance)
> ...and the other thing is I don't trust the discount approvals process at all.
> I've seen orders go out at 50%+ off. On some of those we must be losing money
> on every single unit. Can somebody please check whether that's true and if so
> how much it's costing us annually?

---------- Forwarded message ----------
From: Anand Mehta (Sales)
> Also worth knowing: we set regional revenue targets at the start of each year
> and I don't think anyone has ever checked them properly against actuals.
> Bhavna has the target sheet somewhere. It's a mess but it's what we have.
```

---

## Your Day 0 task (60 minutes)

Turn that into a question register. Concretely:

1. **List every distinct thing being asked**, including the things asked indirectly. Priya lists
   five bullets, but there are asks buried in the prose and in both forwards. Ritu's forward is a
   *specific, costed* question. Anand's is a whole second data source.
2. **Give each an ID and a group.** Use a prefix per theme (`SP` sales performance, `PP` product,
   `CA` customer, `RP` regional, `RT` returns, and one more group you will need to invent for the
   thing Anand mentions).
3. **For each question, write down what "answered" looks like** — a number, a ranked list, a
   trend, a yes/no with evidence. If you cannot say what the output shape is, the question is
   still too vague. Sharpen it.
4. **Mark the three or four that are actually *decisions*** rather than observations. Priya says
   it explicitly: she needs things to DO. Those questions are the point of the project; everything
   else is supporting evidence.
5. Write them into `analysis/questions.md` using the template already there.

Aim for **22-30 questions.** Fewer means you missed things. Many more means you are not grouping.

### What good looks like

A vague ask becomes a sharp question when it has a **subject, a metric, a comparison, and a
period**:

| Priya said | Too vague | Sharp enough to query |
|---|---|---|
| "how we're actually doing" | "Analyse sales" | "SP2: How have monthly revenue and profit changed year over year, and which months drove the change?" |
| "returns are eating us alive" | "Look at returns" | "RT4: What is total revenue and profit lost to returns, as an absolute figure and as a % of gross, by category?" |
| Ritu's forward | "Check discounts" | "PP6: At what discount rate does contribution margin turn negative, by sub-category, and what did discounting above that threshold cost last year?" |

Notice the third one is a **decision question** — its answer is a number you can put a policy on.

---

## After you have written yours

Open `_SEALED-question-list.md` and compare. It holds the 25 questions this project was
originally built around.

Score yourself honestly, in `analysis/learning-log.md`:

- **Matched** — you asked it too (in substance, not wording)
- **Missed** — it is there, you did not think of it. *Write one line on why.* This is the
  valuable column.
- **Extra** — you asked something the list does not have. Keep the good ones; they are yours,
  and being able to say "I added the discount-threshold analysis myself because Finance raised
  it" is a strong interview line.

Then **merge** the two lists and build against the merged register. Do not discard yours.

> Typical first attempt lands 14-19 of 25. That is a completely normal score. The misses are
> almost always the same shapes: no seasonality question, no AOV, no "consistently
> underperforming" (as distinct from "worst"), and no explicit *why did it change* question.

---

## The three questions your final write-up must answer

Priya's real ask, restated in the standard analyst frame. Every finding on Day 4 rolls up here.

1. **What is happening?** — current sales, product, customer, regional performance.
2. **Why is it happening?** — the mechanism behind each change. Not "profit fell" but "profit
   fell *because*".
3. **What should we do?** — 2-3 decisions, each with a rupee figure and a stated trade-off.

And the constraint Priya set, which is really about validation: *"whatever you show me, I need to
know you can prove it."* That is why the reconciliation gates exist. The Central-region incident
in her email is a fan-out bug (returned orders counted as sales) — exactly the failure mode the
Day 1 gate is designed to catch.
