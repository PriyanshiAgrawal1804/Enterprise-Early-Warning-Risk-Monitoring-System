# Power BI Dashboard Architecture — EWRMS

This project is designed to plug directly into Power BI. Since Power BI
`.pbix` files are binary and platform-specific, this folder documents the
**exact architecture, pages, and DAX measures** so the dashboard can be
rebuilt in minutes by connecting Power BI to the data produced by this
pipeline (`outputs/processed_data/loan_data_with_risk_scores.csv` or the
`ewrms.loan_portfolio_clean` SQL table).

## Data connections

| Source | Connects to |
|---|---|
| SQL Data Warehouse | `ewrms.loan_portfolio_clean`, `ewrms.employee_activity_log`, `ewrms.macro_indicators` |
| Python Model Output | `outputs/processed_data/loan_data_with_risk_scores.csv` (risk_score, risk_segment) |
| Excel | `outputs/EWRMS_KPI_Dashboard.xlsx` (KPI Summary for quick reference / offline sharing) |

Recommended refresh: nightly, after the SQL + Python pipeline jobs complete.

## Page 1 — Executive Summary
**Audience:** CRO / Senior Management

- KPI cards: Total Portfolio Value, Charge-Off Rate, Bad Loan Rate, Avg Risk Score
- Monthly Bad Loan Rate trend line (early warning signal)
- Portfolio composition donut: Good vs Bad loans
- Regional heat map: bad loan rate by region

## Page 2 — Loan Portfolio Risk Monitoring
**Audience:** Risk / Credit Committee

- Risk segment distribution (Low-Risk / Moderate-Risk / Watch-list / Distressed)
- FICO bucket distribution with drill-through to loan-level detail
- DTI & LTI ratio distributions with high-risk threshold markers
- Table: top 50 highest risk_score loans, sortable, with drill-through

## Page 3 — Risk Driver Analysis ("What-If")
**Audience:** Risk Analysts / Modelers

- DAX "What-If" parameter for a hypothetical interest-rate shock or income shock
- Feature-importance visual (imported from `outputs/images/10_feature_importance.png`
  or rebuilt natively with a Power BI decomposition tree)
- Scenario table: projected charge-off rate under stressed macro assumptions
  (joined with `ewrms.macro_indicators`)

## Page 4 — Borrower Risk Profile
**Audience:** Relationship Managers

- Search/slicer by customer_id or loan_id
- Individual borrower's risk_score, risk_segment, DTI, LTI, FICO trend
- Repayment history mini-chart
- Recommended action based on risk_score_band (informational, not automated)

## Page 5 — Operational & Fraud Monitoring
**Audience:** Internal Audit / Fraud & Compliance

- Anomaly Detection Alerts KPI card (from `employee_activity_flagged.csv`)
- Employee activity scatter (off-hours access vs bulk downloads), anomalies highlighted
- Table of flagged employees with anomaly_score, drill-through to their loan book

## Example DAX measures

```dax
Charge-Off Rate =
DIVIDE(
    CALCULATE(SUM(loan_portfolio_clean[loan_amount]), loan_portfolio_clean[loan_status_group] = "Bad"),
    SUM(loan_portfolio_clean[loan_amount])
)

Avg Risk Score =
AVERAGE(loan_portfolio_clean[risk_score])

High Risk Loan Count =
CALCULATE(
    COUNTROWS(loan_portfolio_clean),
    loan_portfolio_clean[risk_score] >= 60
)

MoM Bad Loan Rate Change =
VAR CurrentRate = [Charge-Off Rate]
VAR PriorRate = CALCULATE([Charge-Off Rate], DATEADD('Calendar'[Date], -1, MONTH))
RETURN CurrentRate - PriorRate
```

## Build steps

1. Open Power BI Desktop → Get Data → SQL Server / PostgreSQL (or CSV import
   for a quick local demo using `outputs/processed_data/loan_data_with_risk_scores.csv`).
2. Load the 4 tables described above and create relationships on `loan_id` /
   `employee_id`.
3. Paste in the DAX measures above (Modeling → New Measure).
4. Recreate the 5 pages using the layout notes above — screenshots of the
   equivalent Python/matplotlib charts are provided in `outputs/images/` as a
   visual reference for chart types and layout while you build.
5. Publish to the Power BI Service and schedule a data-refresh matching the
   pipeline's run cadence.
