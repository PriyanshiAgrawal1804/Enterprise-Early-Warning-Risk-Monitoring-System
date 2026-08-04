/* ============================================================
   Enterprise Early Warning Risk Monitoring System (EWRMS)
   03_kpi_queries.sql

   Purpose: Library of KPI queries that back the Power BI /
   Excel reporting layer (Phase 3). Each query corresponds to a
   KPI in the README's KPI Tracking Framework.
   ============================================================ */

-- 1. Default / Charge-Off Rate (Lagging)
SELECT
    ROUND(100.0 * SUM(CASE WHEN loan_status_group = 'Bad' THEN loan_amount ELSE 0 END)
          / NULLIF(SUM(loan_amount), 0), 2) AS charge_off_rate_pct
FROM ewrms.loan_portfolio_clean;

-- 2. Good Loan / Bad Loan % by region
SELECT
    region,
    ROUND(100.0 * COUNT(*) FILTER (WHERE loan_status_group = 'Good') / COUNT(*), 2) AS good_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE loan_status_group = 'Bad')  / COUNT(*), 2) AS bad_pct
FROM ewrms.loan_portfolio_clean
GROUP BY region
ORDER BY bad_pct DESC;

-- 3. Average Interest Rate by risk segment
SELECT risk_segment, ROUND(AVG(interest_rate), 2) AS avg_interest_rate
FROM ewrms.loan_portfolio_clean
GROUP BY risk_segment;

-- 4. DTI distribution (high-risk = DTI > 0.40)
SELECT
    ROUND(AVG(dti_ratio), 4) AS avg_dti,
    ROUND(100.0 * COUNT(*) FILTER (WHERE dti_ratio > 0.40) / COUNT(*), 2) AS pct_high_dti_borrowers
FROM ewrms.loan_portfolio_clean;

-- 5. FICO bucket distribution
SELECT fico_bucket, COUNT(*) AS num_loans,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_portfolio
FROM ewrms.loan_portfolio_clean
GROUP BY fico_bucket
ORDER BY num_loans DESC;

-- 6. Loan-to-Income (LTI) - over-leveraged borrower flag (LTI > 4)
SELECT COUNT(*) AS overleveraged_borrowers
FROM ewrms.loan_portfolio_clean
WHERE lti_ratio > 4;

-- 7. Average Model Risk Score by segment (Leading indicator)
SELECT risk_segment, ROUND(AVG(risk_score), 2) AS avg_risk_score, COUNT(*) AS num_customers
FROM ewrms.loan_portfolio_clean
GROUP BY risk_segment
ORDER BY avg_risk_score DESC;

-- 8. Anomaly / Fraud Alerts - count of flagged employee activity
SELECT employee_id,
       COUNT(*) FILTER (WHERE anomaly_flag = 1) AS flagged_events,
       COUNT(*) AS total_events
FROM ewrms.employee_activity_log
GROUP BY employee_id
HAVING COUNT(*) FILTER (WHERE anomaly_flag = 1) > 0
ORDER BY flagged_events DESC;

-- 9. Portfolio-level trend: monthly bad-loan rate (for the Executive Summary page)
SELECT
    DATE_TRUNC('month', r.issue_date) AS month,
    ROUND(100.0 * COUNT(*) FILTER (WHERE c.loan_status_group = 'Bad') / COUNT(*), 2) AS bad_loan_rate_pct
FROM ewrms.loan_portfolio_raw r
JOIN ewrms.loan_portfolio_clean c ON r.loan_id = c.loan_id
GROUP BY 1
ORDER BY 1;
