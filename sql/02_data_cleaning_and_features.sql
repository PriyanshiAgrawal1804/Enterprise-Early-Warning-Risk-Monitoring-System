/* ============================================================
   Enterprise Early Warning Risk Monitoring System (EWRMS)
   02_data_cleaning_and_features.sql

   Purpose: Cleans the raw loan portfolio table and derives the
   engineered features used across EDA, segmentation, and the
   predictive model. Mirrors the logic implemented in
   python/01_data_cleaning.py and python/02_feature_engineering.py
   so the same transformations can run natively inside the
   warehouse for production scheduling (e.g. via a nightly job).
   ============================================================ */

-- ------------------------------------------------------------
-- 1. Remove exact duplicate loan records
-- ------------------------------------------------------------
DELETE FROM ewrms.loan_portfolio_raw a
USING ewrms.loan_portfolio_raw b
WHERE a.ctid < b.ctid
  AND a.loan_id = b.loan_id;

-- ------------------------------------------------------------
-- 2. Impute missing income / FICO with cohort medians
-- ------------------------------------------------------------
WITH income_median AS (
    SELECT employment_type, region,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY annual_income) AS median_income
    FROM ewrms.loan_portfolio_raw
    WHERE annual_income IS NOT NULL
    GROUP BY employment_type, region
)
UPDATE ewrms.loan_portfolio_raw r
SET annual_income = im.median_income
FROM income_median im
WHERE r.annual_income IS NULL
  AND r.employment_type = im.employment_type
  AND r.region = im.region;

UPDATE ewrms.loan_portfolio_raw
SET fico_score = (SELECT ROUND(AVG(fico_score)) FROM ewrms.loan_portfolio_raw WHERE fico_score IS NOT NULL)
WHERE fico_score IS NULL;

-- ------------------------------------------------------------
-- 3. Build the curated table with engineered features
-- ------------------------------------------------------------
INSERT INTO ewrms.loan_portfolio_clean (
    loan_id, customer_id, age, gender, region, employment_type,
    loan_purpose, loan_amount, term_months, interest_rate,
    annual_income, fico_score, fico_bucket, credit_history_months,
    dti_ratio, lti_ratio, loan_status_group
)
SELECT
    loan_id,
    customer_id,
    age,
    gender,
    region,
    employment_type,
    loan_purpose,
    loan_amount,
    term_months,
    interest_rate,
    annual_income,
    fico_score,

    -- FICO bucket (leading indicator category used on dashboards)
    CASE
        WHEN fico_score < 580 THEN 'Poor'
        WHEN fico_score < 670 THEN 'Fair'
        WHEN fico_score < 740 THEN 'Good'
        WHEN fico_score < 800 THEN 'Very Good'
        ELSE 'Excellent'
    END AS fico_bucket,

    -- credit_history_months = (issue_date - earliest_credit_line) in months
    (DATE_PART('year', AGE(issue_date, earliest_credit_line)) * 12
     + DATE_PART('month', AGE(issue_date, earliest_credit_line)))::INT AS credit_history_months,

    -- Debt-to-Income (DTI): monthly_installment / (annual_income / 12)
    ROUND((monthly_installment / NULLIF(annual_income / 12.0, 0))::NUMERIC, 4) AS dti_ratio,

    -- Loan-to-Income (LTI): total loan amount / annual income
    ROUND((loan_amount / NULLIF(annual_income, 0))::NUMERIC, 4) AS lti_ratio,

    -- loan_status_group: 'Good' vs 'Bad'
    CASE
        WHEN loan_status IN ('Fully Paid', 'Current') THEN 'Good'
        WHEN loan_status IN ('Charged Off', 'Default') THEN 'Bad'
        ELSE 'Unknown'
    END AS loan_status_group

FROM ewrms.loan_portfolio_raw;
