# User test — protocol and findings

The Day 5 block that cannot be simulated. The entire value of a user test is discovering what a
**stranger** misreads, and there is no way to generate that from the inside: the person who built
the dashboard cannot un-know how it works.

**Status: outstanding.** Run this once the `.pbix` is assembled. It takes 30 minutes and it is the
single highest-value half-hour left in the project.

---

## Protocol

1. Hand the file to **one real person** who has not seen it. A non-analyst is better than an
   analyst — Priya is not an analyst.
2. Say exactly this and nothing else: *"You're the Head of Commercial. You have a board meeting in
   ten minutes. Tell me what's going on with the business."*
3. **Then stop talking.** Every explanation offered is a finding destroyed. If they ask what
   something means, write the question down and say "what do you think it means?"
4. Write down, verbatim:
   - every question they ask
   - every number they read out **wrong**
   - every place they click that does nothing
   - every place they *do not* click that they should have
   - how long before they say something about margin
5. Fix the **two worst** things. Ignore the rest. A user test that generates a 20-item backlog on
   Day 5 has been mis-scoped.

---

## Findings

*(to be filled during the session)*

| # | What they did / asked | What it means | Severity | Fixed? |
|---|---|---|---|---|
| | | | | |

---

## The two fixes I made

*(to be filled — exactly two)*

1.
2.

---

## What to watch for specifically

These are the places this build is most likely to be misread. Written **before** the test so they
count as predictions rather than post-hoc rationalisation — if the test finds something not on this
list, that is the valuable result.

| Prediction | Why I expect it |
|---|---|
| They read "Revenue" as net of returns | It is gross. The label says so, but nobody reads labels. If they misread it, the fix is renaming the measure `Revenue (gross)`, not adding a footnote |
| They read the upper bound of the counterfactual as *the* answer | It is the friendlier number and it is on the left. If this happens, put the range in the card title rather than in two separate cards |
| They cannot tell "margin fell 2.49 pp" from "margin fell 2.49%" | Percentage points versus percent is the most common misreading in any margin dashboard. The measure is named `Margin Change (pp)` for this reason; watch whether the name survives contact |
| They try to click a KPI card to filter the page | Cross-filtering is deliberately off on the cards. If they try it repeatedly, that is a real finding about their mental model, not about the cards |
| They ask "which products should we drop?" | The answer is *none* — no product loses money — but the page is organised around discount bands and may not make that obvious enough. This is the finding most likely to change a visual |
| They do not notice the returns caveat on Page 4 | The attribution caveat (a return is recorded against an order, not a line) is in a subtitle. Subtitles get skipped. If they quote a category return rate as "items sent back", the caveat needs to be in the title |
| They take longer than 60 seconds to say anything about margin | Page 1 was rebuilt around margin recovery specifically so this would not happen. If it still does, the page has failed at its one job |
