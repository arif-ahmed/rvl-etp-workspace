# GoBCB Feature Matrix

`GoBCB-Feature-Matrix.xlsx` is a generated, non-developer-friendly view of the
[feature documentation](../feature-docs/) plus the working tracker for the BS-23
verification review.

## Sheets

| Sheet | For | What it holds |
|---|---|---|
| Cover & Legend | everyone | purpose, per-role reading guide, evidence baseline, status legends |
| Summary | PM / HoE | features per area, open queries per kind, verification progress (live formulas) |
| Feature Matrix | all | one row per feature (103): area, module, plain-language purpose, actor, services, endpoints, dependencies, open queries, defect risk, testability, doc link + **BS-23 status & comments** |
| Open Queries | BS-23 session | all 75 queries (Q-01…Q-77, Q-21/Q-24 unused) with kind, evidence, cited features + **response columns** |
| Closure Cross-Check | BS-23 session | 25 findings from RVL's review of the BS-23 closure report (`../BS23_GOBCB_eTicketing_Project_Closure_and_Handover_Report_V1.2.pdf`): gaps, discrepancies, questions, deliverables to obtain — with verdicts, actions, owners and **status + notes columns** |
| Traceability | DEV / OPS | feature → service, primary endpoint, queues, Redis keys, local state, external systems |
| Gap Log | BS-23 session | anything the documentation missed — add rows freely |
| Review | integrity | live self-checks (row counts, totals) — all rows should read PASS |

## Rules

- The markdown docs under `../feature-docs/` are the **source of truth**. This
  workbook is a generated view; do not hand-edit the generated columns (A–P on
  Feature Matrix, B–F on Open Queries, everything on Traceability).
- Only the review columns are yours: **BS-23 status + comments** (Feature
  Matrix), **response / status / answered-by / date** (Open Queries), **status +
  notes** (Closure Cross-Check), and the whole **Gap Log**.
- The Closure Cross-Check sheet is generated from
  [`closure-crosscheck.json`](closure-crosscheck.json) — edit that file to change
  the findings, then regenerate; status and notes entered in the workbook are
  preserved.

## Regenerating after the docs change

```bash
python scripts/generate_feature_matrix.py            # needs Python 3.9+ and openpyxl
```

Regeneration **preserves review entries**: statuses, comments, query responses
and gap rows are read back from the existing workbook and merged by feature or
query id, so nothing typed during a review session is lost. Use `--no-preserve`
to force a clean sheet. The generator aborts (rather than emitting a partial
workbook) if the docs no longer match the expected shape: 103 features
(31 admin / 13 portal / 10 app / 6 checker / 17 system / 26 cross-cutting) and
75 open queries.

Known source-doc quirk: `99-open-queries.md` §1 lists Q-77 as *Ambiguity* and
Q-27 as *Defect*, but both the section headings and tables place Q-27 under
Ambiguities and Q-77 under Defects. The workbook follows the tables and the
generator prints a warning about the mismatch.
