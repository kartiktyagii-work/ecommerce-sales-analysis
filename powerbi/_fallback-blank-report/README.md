# Fallback — use this only if the generated report will not open

The `.pbip` in the folder above ships a full four-page report authored as PBIR text files.
It was validated statically (every field reference resolves against the model, every JSON file
parses) but it could not be opened in Power BI Desktop before delivery, so a visual-level
rejection is possible.

**If Power BI Desktop refuses to open the report, or a page fails to load:**

1. Close Power BI Desktop.
2. Rename `../ecommerce-sales-analysis.Report` to `../_broken.Report`.
3. Copy `ecommerce-sales-analysis.Report` from this folder up one level.
4. Re-open `../ecommerce-sales-analysis.pbip`.

You now have the **complete semantic model** — 11 tables, 59 measures in 9 display folders,
7 relationships, `dim_date` marked as a date table, both what-if parameters and both RLS roles —
with one blank page. Build the four pages from `../BUILD-RUNBOOK.md` Phases 1-4, which is the
work this was trying to save you and nothing more.

Nothing else is lost: the model is the part that takes two hours and the part where a mis-click
silently produces a wrong number. The visuals are drag-and-drop.
