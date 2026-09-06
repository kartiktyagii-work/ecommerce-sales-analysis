# Question register — YOU write this

Empty on purpose. Fill it on Day 0 from [`../STAKEHOLDER-BRIEF.md`](../STAKEHOLDER-BRIEF.md).

**Why it is empty:** being handed 25 pre-written questions skips the hardest and most-tested part
of the job. Deriving them yourself is the exercise. Compare against
[`../_SEALED-question-list.md`](../_SEALED-question-list.md) *after* you write yours, then merge.

---

## How to fill this in

| Column | What goes in it | When |
|---|---|---|
| **ID** | Group prefix + number: `SP1`, `PP3`, `CA2`... | Day 0 |
| **Question** | One sentence with a subject, metric, comparison and period | Day 0 |
| **Type** | `D` descriptive (what) · `X` diagnostic (why) · `!` decision (what to do) | Day 0 |
| **Query** | The `.sql` file that answers it | as you build |
| **Visual** | Page + visual that shows it | Day 3 |
| **Answer** | The headline number, written the day you run the query | as you run |

Two rules that make this file worth keeping:

- **A question with no query is a question you did not answer.**
- **A query with no visual is analysis nobody will see.**

The **Answer** column is doing double duty: it is the baseline your DAX gets checked against on
Day 3's gate, and it is the raw material for the Day 4 write-up. Fill it in *the day you run the
query*, not later from memory.

Aim for at least four rows marked `!`. A register with no decision questions produces a
dashboard nobody acts on.

---

## Sales performance — SP

| ID | Question | Type | Query | Visual | Answer |
|---|---|---|---|---|---|
| SP1 | | | | | |
| SP2 | | | | | |
| SP3 | | | | | |

## Product performance — PP

| ID | Question | Type | Query | Visual | Answer |
|---|---|---|---|---|---|
| PP1 | | | | | |
| PP2 | | | | | |
| PP3 | | | | | |

## Customer analytics — CA

| ID | Question | Type | Query | Visual | Answer |
|---|---|---|---|---|---|
| CA1 | | | | | |
| CA2 | | | | | |
| CA3 | | | | | |

## Regional performance — RP

| ID | Question | Type | Query | Visual | Answer |
|---|---|---|---|---|---|
| RP1 | | | | | |
| RP2 | | | | | |

## Returns — RT

| ID | Question | Type | Query | Visual | Answer |
|---|---|---|---|---|---|
| RT1 | | | | | |
| RT2 | | | | | |

## _______________ — __

> Add your own group here. There is at least one theme in the brief that none of the five
> prefixes above covers. Finding it is part of the Day 0 exercise.

| ID | Question | Type | Query | Visual | Answer |
|---|---|---|---|---|---|
| | | | | | |

---

## Coverage check — fill in on Day 0, revisit after the Day 3 change request

| Group | Questions | Of which decisions (`!`) | Day answered |
|---|---|---|---|
| SP | | | |
| PP | | | |
| CA | | | |
| RP | | | |
| RT | | | |
| | | | |
| **Total** | | | |

## Roll-up to the three management questions

Map your IDs to each. Anything that maps to nothing is a question you should probably cut.

1. **What is happening?** — IDs:
2. **Why is it happening?** — IDs:
3. **What should the business do?** — IDs:
