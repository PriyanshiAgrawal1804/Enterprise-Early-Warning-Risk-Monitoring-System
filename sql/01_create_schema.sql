/* ============================================================
   Enterprise Early Warning Risk Monitoring System (EWRMS)
   01_create_schema.sql

   Purpose: Creates the centralized SQL data warehouse schema
   that receives extracts from the Loan Origination System (LOS),
   core banking transactional systems, and the internal access-
   log system. This is the landing zone (Phase 1 of the pipeline).
   ============================================================ */

CREATE SCHEMA IF NOT EXISTS ewrms;

-- ------------------------------------------------------------
-- 1. Raw loan portfolio table (1 row per loan account)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ewrms.loan_portfolio_raw (
    loan_id                     VARCHAR(20)     PRIMARY KEY,
    customer_id                 VARCHAR(20)     NOT NULL,
    age                         SMALLINT,
    gender                      VARCHAR(10),
    region                      VARCHAR(20),
    employment_type             VARCHAR(30),
    loan_purpose                VARCHAR(40),
    loan_amount                 NUMERIC(14,2),
    term_months                 SMALLINT,
    interest_rate                NUMERIC(5,2),
    annual_income                NUMERIC(14,2),
    issue_date                  DATE,
    earliest_credit_line        DATE,
    fico_score                  SMALLINT,
    num_delinquencies_2yrs      SMALLINT,
    open_credit_lines           SMALLINT,
    revolving_utilization_pct   NUMERIC(6,2),
    overdraft_count_6m          SMALLINT,
    cashflow_volatility_score   NUMERIC(10,2),
    monthly_installment         NUMERIC(12,2),
    handled_by_employee_id      VARCHAR(20),
    off_hours_access_flag       SMALLINT,
    bulk_download_flag          SMALLINT,
    loan_status                 VARCHAR(20),
    load_timestamp               TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

-- ------------------------------------------------------------
-- 2. Cleaned / curated portfolio table (output of Phase 1)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ewrms.loan_portfolio_clean (
    loan_id                     VARCHAR(20)     PRIMARY KEY,
    customer_id                 VARCHAR(20),
    age                         SMALLINT,
    gender                      VARCHAR(10),
    region                      VARCHAR(20),
    employment_type             VARCHAR(30),
    loan_purpose                VARCHAR(40),
    loan_amount                 NUMERIC(14,2),
    term_months                 SMALLINT,
    interest_rate                NUMERIC(5,2),
    annual_income                NUMERIC(14,2),
    fico_score                  SMALLINT,
    fico_bucket                 VARCHAR(20),
    credit_history_months        INT,
    dti_ratio                   NUMERIC(6,4),
    lti_ratio                   NUMERIC(6,4),
    loan_status_group            VARCHAR(10),   -- 'Good' / 'Bad'
    risk_score                  NUMERIC(5,2),   -- populated by ML model
    risk_segment                VARCHAR(20)     -- populated by K-Means
);

-- ------------------------------------------------------------
-- 3. Employee / operational activity log
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ewrms.employee_activity_log (
    activity_id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id                 VARCHAR(20),
    loan_id                     VARCHAR(20),
    activity_timestamp           TIMESTAMP,
    off_hours_access_flag        SMALLINT,
    bulk_download_flag           SMALLINT,
    anomaly_flag                SMALLINT DEFAULT 0
);

-- ------------------------------------------------------------
-- 4. Macroeconomic / external indicators (secondary source)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ewrms.macro_indicators (
    period_month                DATE PRIMARY KEY,
    repo_rate                   NUMERIC(5,2),
    unemployment_rate            NUMERIC(5,2),
    inflation_rate               NUMERIC(5,2),
    gdp_growth_rate              NUMERIC(5,2)
);

-- Helpful indexes for the dashboard's most common filters
CREATE INDEX IF NOT EXISTS idx_clean_region ON ewrms.loan_portfolio_clean(region);
CREATE INDEX IF NOT EXISTS idx_clean_status ON ewrms.loan_portfolio_clean(loan_status_group);
CREATE INDEX IF NOT EXISTS idx_clean_segment ON ewrms.loan_portfolio_clean(risk_segment);
