USE EWS;

# 0.1 Cleaned account dimension
CREATE VIEW v_account AS
SELECT
    account_key, account_id, customer_key, product_key, branch_key,
    UPPER(TRIM(account_type)) AS account_type,
    sanction_amount, disbursed_amount, interest_rate, tenure_months,
    account_open_date,
    UPPER(TRIM(account_status)) AS account_status,   -- ACTIVE / CLOSED / WRITTEN-OFF
    UPPER(TRIM(security_type)) AS security_type,
    UPPER(TRIM(consortium_flag)) = 'TRUE' AS is_consortium
FROM dim_account;

# 0.2 Cleaned branch dimension 
CREATE VIEW v_branch AS
SELECT branch_key, branch_code,
       UPPER(TRIM(branch_name)) AS branch_name,
       TRIM(region) AS region, TRIM(zone) AS zone,
       TRIM(state) AS state, TRIM(country) AS country
FROM dim_branch;

# 0.3 Cleaned customer dimension
CREATE VIEW v_customer AS
SELECT
    customer_key, customer_id, TRIM(customer_name) AS customer_name,
    UPPER(TRIM(customer_type)) AS customer_type,
    pan_number, date_of_birth, incorporation_date,
    TRIM(industry_sector) AS industry_sector,
    UPPER(TRIM(kyc_risk_category)) AS kyc_risk_category,  
    relationship_manager_id, onboarding_date,
    credit_rating_internal, credit_rating_external,
    UPPER(TRIM(is_pep)) = 'TRUE' AS is_pep
FROM dim_customer;

# 0.4 Cleaned account performance fact
CREATE VIEW v_perf AS
SELECT
    fact_id, account_key, customer_key, snapshot_date,
    outstanding_balance, overdue_amount, dpd_days,
    TRIM(dpd_bucket) AS dpd_bucket,
    UPPER(TRIM(sma_category)) AS sma_category,     -- STANDARD/SMA-0/SMA-1/SMA-2/NPA
    emi_amount,
    UPPER(TRIM(emi_bounce_flag)) = 'TRUE' AS emi_bounced,
    credit_utilization_ratio,
    UPPER(TRIM(min_due_paid_flag)) = 'TRUE' AS min_due_paid,
    provision_amount,
    UPPER(TRIM(restructured_flag)) = 'TRUE' AS is_restructured
FROM fact_account_performance;

# 0.5 Cleaned transaction fact
CREATE VIEW v_txn AS
SELECT
    transaction_id, account_key, customer_key, transaction_timestamp,
    UPPER(TRIM(transaction_type)) AS transaction_type,
    UPPER(TRIM(channel)) AS channel,
    amount, counterparty_account_id, TRIM(geo_location) AS geo_location,
    UPPER(TRIM(is_flagged_fraud)) = 'TRUE' AS is_flagged_fraud,
    fraud_score, UPPER(TRIM(status)) AS status
FROM fact_transaction;

# 0.6 Cleaned risk score fact
CREATE VIEW v_risk AS
SELECT score_id, TRIM(entity_type) AS entity_type, entity_key,
       UPPER(TRIM(risk_domain)) AS risk_domain,     -- CREDIT/MARKET/LIQUIDITY/FRAUD
       raw_score, normalized_score,
       UPPER(TRIM(risk_band)) AS risk_band,         -- GREEN/AMBER/RED
       score_date
FROM risk_score;

# 0.7 Cleaned alert fact
CREATE VIEW v_alert AS
SELECT alert_id, TRIM(entity_type) AS entity_type, entity_key, score_id,
       alert_date,
       UPPER(TRIM(severity)) AS severity,           -- LOW/MEDIUM/HIGH/CRITICAL
       TRIM(alert_status) AS alert_status,           -- Open/Assigned/Closed/False-Positive
       assigned_to, sla_due_date
FROM alert;

#  SECTION 1 — SIMPLE: exploration, counts, distincts

# 1.1 Row counts across all tables
SELECT 'dim_account' t, COUNT(*) n FROM dim_account
UNION ALL SELECT 'dim_branch', COUNT(*) FROM dim_branch
UNION ALL SELECT 'dim_customer', COUNT(*) FROM dim_customer
UNION ALL SELECT 'dim_product', COUNT(*) FROM dim_product
UNION ALL SELECT 'fact_account_performance', COUNT(*) FROM fact_account_performance
UNION ALL SELECT 'fact_transaction', COUNT(*) FROM fact_transaction
UNION ALL SELECT 'risk_score', COUNT(*) FROM risk_score
UNION ALL SELECT 'alert', COUNT(*) FROM alert;

# 1.2 Distinct account statuses
SELECT DISTINCT account_status FROM dim_account;

# 1.3 Distinct risk bands and alert severities
SELECT DISTINCT risk_band FROM v_risk;
SELECT DISTINCT severity FROM v_alert;

# 1.4 Product catalogue 
SELECT * FROM dim_product;

# 1.5 Count of accounts by cleaned status
SELECT account_status, COUNT(*) AS n
FROM v_account
GROUP BY account_status
ORDER BY n DESC;

# SECTION 2 — FILTERING & BASIC AGGREGATION

# 2.1 All accounts currently in NPA
SELECT account_key, sma_category, dpd_days, overdue_amount
FROM v_perf
WHERE sma_category = 'NPA'
ORDER BY overdue_amount DESC
LIMIT 20;

# 2.2 Total sanctioned vs disbursed exposure by product
SELECT p.product_name,
       COUNT(*) AS n_accounts,
       ROUND(SUM(a.sanction_amount),2) AS total_sanctioned,
       ROUND(SUM(a.disbursed_amount),2) AS total_disbursed
FROM v_account a
JOIN dim_product p ON a.product_key = p.product_key
GROUP BY p.product_name
ORDER BY total_disbursed DESC;

# 2.3 High/Critical open alerts, unresolved
SELECT alert_id, entity_type, entity_key, severity, alert_status, alert_date
FROM v_alert
WHERE severity IN ('HIGH','CRITICAL') AND alert_status NOT IN ('Closed','False-Positive')
ORDER BY severity DESC;

# 2.4 Customers flagged as Politically Exposed Persons (PEP) with HIGH KYC risk classic compliance early-warning filter
SELECT customer_id, customer_name, customer_type, industry_sector
FROM v_customer
WHERE is_pep = 1 AND kyc_risk_category = 'HIGH';

# 2.5 Transactions flagged as fraud, above a materiality threshold
SELECT transaction_id, account_key, amount, channel, fraud_score, status
FROM v_txn
WHERE is_flagged_fraud = 1 AND amount > 50000
ORDER BY amount DESC
LIMIT 20;

#  SECTION 3 — JOINS ACROSS THE STAR SCHEMA

# 3.1 Full 360 view of an account: customer + branch + product + latest performance snapshot (using MAX(snapshot_date) as text -- acceptable only where dates share a sortable format
SELECT a.account_id, c.customer_name, b.branch_name, p.product_name,
       a.account_status, a.disbursed_amount
FROM v_account a
JOIN v_customer c ON a.customer_key = c.customer_key
JOIN v_branch b   ON a.branch_key = b.branch_key
JOIN dim_product p ON a.product_key = p.product_key
LIMIT 20;

# 3.2 Exposure at risk by region: active accounts currently in SMA-2 or NPA
SELECT b.region, COUNT(DISTINCT a.account_key) AS accounts_at_risk,
       ROUND(SUM(f.overdue_amount),2) AS total_overdue
FROM v_perf f
JOIN v_account a ON f.account_key = a.account_key
JOIN v_branch b  ON a.branch_key = b.branch_key
WHERE f.sma_category IN ('SMA-2','NPA')
GROUP BY b.region
ORDER BY total_overdue DESC;

# 3.3 Alerts joined to their originating risk score and the entity's branch (only for entity_type = 'Account')
SELECT al.alert_id, al.severity, al.alert_status,
       rs.risk_domain, rs.risk_band, rs.normalized_score,
       b.branch_name, b.region
FROM v_alert al
JOIN v_risk rs ON al.score_id = rs.score_id
JOIN v_account a ON al.entity_key = a.account_key AND al.entity_type = 'Account'
JOIN v_branch b ON a.branch_key = b.branch_key
ORDER BY al.severity DESC
LIMIT 20;

# 3.4 High-value SME/Corporate customers with a RED risk band on any domain
SELECT c.customer_name, c.customer_type, c.industry_sector,
       rs.risk_domain, rs.risk_band, rs.normalized_score
FROM v_risk rs
JOIN v_customer c ON rs.entity_key = c.customer_key AND rs.entity_type = 'Customer'
WHERE rs.risk_band = 'RED' AND c.customer_type IN ('SME','CORPORATE')
ORDER BY rs.normalized_score DESC;

# 3.5 Restructured accounts and their current arrears status
SELECT a.account_id, c.customer_name, f.dpd_days, f.sma_category, f.overdue_amount
FROM v_perf f
JOIN v_account a  ON f.account_key = a.account_key
JOIN v_customer c ON f.customer_key = c.customer_key
WHERE f.is_restructured = 1
ORDER BY f.dpd_days DESC
LIMIT 20;

# SECTION 4 — WINDOW FUNCTIONS: TREND & DETERIORATION TRACKING

# 4.1 Latest snapshot per account
WITH ranked AS (
    SELECT f.*,
           ROW_NUMBER() OVER (PARTITION BY account_key ORDER BY fact_id DESC) AS rn
    FROM v_perf f
)
SELECT account_key, snapshot_date, dpd_days, sma_category, overdue_amount
FROM ranked
WHERE rn = 1
ORDER BY dpd_days DESC
LIMIT 20;

# 4.2 DPD trend per account: current vs. previous snapshot (bucket migration)
WITH seq AS (
    SELECT f.*,
           ROW_NUMBER() OVER (PARTITION BY account_key ORDER BY fact_id) AS seq_no
    FROM v_perf f
),
paired AS (
    SELECT curr.account_key,
           prev.sma_category AS prev_bucket,
           curr.sma_category AS curr_bucket,
           prev.dpd_days AS prev_dpd,
           curr.dpd_days AS curr_dpd
    FROM seq curr
    JOIN seq prev ON curr.account_key = prev.account_key AND curr.seq_no = prev.seq_no + 1
)
SELECT prev_bucket, curr_bucket, COUNT(*) AS n_accounts
FROM paired
GROUP BY prev_bucket, curr_bucket
ORDER BY n_accounts DESC;

# 4.3 Accounts whose DPD increased for 2+ consecutive snapshots in a row
WITH seq AS (
    SELECT f.*,
           ROW_NUMBER() OVER (PARTITION BY account_key ORDER BY fact_id) AS seq_no,
           LAG(dpd_days) OVER (PARTITION BY account_key ORDER BY fact_id) AS prev_dpd
    FROM v_perf f
),
flagged AS (
    SELECT account_key, seq_no, dpd_days, prev_dpd,
           CASE WHEN prev_dpd IS NOT NULL AND dpd_days > prev_dpd THEN 1 ELSE 0 END AS worsened
    FROM seq
)
SELECT account_key, COUNT(*) AS worsening_snapshots
FROM flagged
WHERE worsened = 1
GROUP BY account_key
HAVING worsening_snapshots >= 2
ORDER BY worsening_snapshots DESC
LIMIT 20;

# 4.4 Credit utilization ratio trend: flag accounts with a sharp jump versus their own historical average (potential liquidity stress signal)
WITH stats AS (
    SELECT account_key,
           credit_utilization_ratio,
           AVG(credit_utilization_ratio) OVER (PARTITION BY account_key) AS avg_util,
           fact_id
    FROM v_perf
    WHERE credit_utilization_ratio IS NOT NULL
)
SELECT account_key, fact_id, credit_utilization_ratio, ROUND(avg_util,3) AS avg_util,
       ROUND(credit_utilization_ratio - avg_util, 3) AS deviation
FROM stats
WHERE credit_utilization_ratio > avg_util * 1.5
ORDER BY deviation DESC
LIMIT 20;

# 4.5 Rank branches by NPA exposure (highest risk concentration first)
WITH branch_npa AS (
    SELECT b.branch_name, b.region, SUM(f.overdue_amount) AS npa_overdue
    FROM v_perf f
    JOIN v_account a ON f.account_key = a.account_key
    JOIN v_branch b ON a.branch_key = b.branch_key
    WHERE f.sma_category = 'NPA'
    GROUP BY b.branch_name, b.region
)
SELECT branch_name, region, ROUND(npa_overdue,2) AS npa_overdue,
       RANK() OVER (ORDER BY npa_overdue DESC) AS risk_rank
FROM branch_npa
ORDER BY risk_rank
LIMIT 15;

# SECTION 5 — DATE HANDLING

# 5.1 Normalize snapshot_date across the formats present into ISO (YYYY-MM-DD)
CREATE VIEW v_perf_dates AS
SELECT
    fact_id,
    account_key,
    snapshot_date AS snapshot_date_raw,

    CASE

        -- YYYY-MM-DD
        WHEN snapshot_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        THEN snapshot_date

        -- YYYY/MM/DD
        WHEN snapshot_date REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'
        THEN CONCAT(
            SUBSTRING(snapshot_date, 1, 4), '-',
            SUBSTRING(snapshot_date, 6, 2), '-',
            SUBSTRING(snapshot_date, 9, 2)
        )

        -- DD-MM-YYYY
        WHEN snapshot_date REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
        THEN CONCAT(
            SUBSTRING(snapshot_date, 7, 4), '-',
            SUBSTRING(snapshot_date, 4, 2), '-',
            SUBSTRING(snapshot_date, 1, 2)
        )

        -- DD/MM/YYYY
        WHEN snapshot_date REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
        THEN CONCAT(
            SUBSTRING(snapshot_date, 7, 4), '-',
            SUBSTRING(snapshot_date, 4, 2), '-',
            SUBSTRING(snapshot_date, 1, 2)
        )

        -- Other formats such as 25 Jul 2026
        ELSE NULL

    END AS snapshot_date_iso

FROM fact_account_performance;

# 5.2 Most recent *reliably parsed* snapshot date per account, and days since
SELECT
    account_key,
    MAX(snapshot_date_iso) AS latest_snapshot,
    DATEDIFF(
        CURDATE(),
        MAX(snapshot_date_iso)
    ) AS days_since_snapshot
FROM v_perf_dates
WHERE snapshot_date_iso IS NOT NULL
GROUP BY account_key
ORDER BY days_since_snapshot DESC
LIMIT 20;

# 5.3 Data-quality audit: proportion of snapshot dates that failed to parse
--     under the numeric formats (i.e., are in "DD Mon YY(YY)" text form and
--     need a month-name mapping table before they're usable
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN snapshot_date_iso IS NOT NULL THEN 1 ELSE 0 END) AS parsed,
    SUM(CASE WHEN snapshot_date_iso IS NULL THEN 1 ELSE 0 END) AS unparsed,
    ROUND(100.0*SUM(CASE WHEN snapshot_date_iso IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_unparsed
FROM v_perf_dates;

# 5.4 SLA breach detection on alerts: alerts still open past their SLA due
--     date. alert_date/sla_due_date share the same mixed formats as above,
--     so this uses the same normalization pattern inline.
WITH alert_dates AS (
    SELECT
        alert_id,
        severity,
        alert_status,

        CASE
            -- DD-MM-YYYY
            WHEN sla_due_date REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
            THEN CONCAT(
                SUBSTRING(sla_due_date, 7, 4), '-',
                SUBSTRING(sla_due_date, 4, 2), '-',
                SUBSTRING(sla_due_date, 1, 2)
            )

            ELSE NULL
        END AS sla_due_iso

    FROM v_alert
)

SELECT
    alert_id,
    severity,
    alert_status,
    sla_due_iso,

    DATEDIFF(
        CURDATE(),
        STR_TO_DATE(sla_due_iso, '%Y-%m-%d')
    ) AS days_past_due

FROM alert_dates

WHERE sla_due_iso IS NOT NULL
  AND alert_status NOT IN ('Closed', 'False-Positive')
  AND STR_TO_DATE(sla_due_iso, '%Y-%m-%d') < CURDATE()

ORDER BY days_past_due DESC

LIMIT 20;

# SECTION 6 — COMPOSITE EARLY WARNING SCORING

# 6.1 Latest performance snapshot per account, joined to customer risk attributes and any open alerts
CREATE VIEW v_account_risk_base AS
WITH latest_perf AS (
    SELECT f.*, ROW_NUMBER() OVER (PARTITION BY account_key ORDER BY fact_id DESC) AS rn
    FROM v_perf f
)
SELECT
    a.account_key, a.account_id, a.account_status, a.disbursed_amount,
    c.customer_id, c.customer_name, c.kyc_risk_category, c.is_pep,
    lp.dpd_days, lp.sma_category, lp.overdue_amount, lp.emi_bounced,
    lp.credit_utilization_ratio, lp.min_due_paid, lp.is_restructured,
    lp.provision_amount
FROM latest_perf lp
JOIN v_account a ON lp.account_key = a.account_key
JOIN v_customer c ON lp.customer_key = c.customer_key
WHERE lp.rn = 1;

# 6.2 Composite early-warning score (0-100, higher = riskier). Each factor
--     contributes points; weights are illustrative and should be tuned to
--     your institution's actual risk appetite / model validation results.
SELECT
    account_id, customer_name,
    dpd_days, sma_category, kyc_risk_category,
    (CASE
        WHEN sma_category = 'NPA' THEN 40
        WHEN sma_category = 'SMA-2' THEN 25
        WHEN sma_category = 'SMA-1' THEN 15
        WHEN sma_category = 'SMA-0' THEN 5
        ELSE 0 END) +
    (CASE WHEN emi_bounced = 1 THEN 15 ELSE 0 END) +
    (CASE WHEN min_due_paid = 0 THEN 10 ELSE 0 END) +
    (CASE WHEN credit_utilization_ratio > 0.9 THEN 15
          WHEN credit_utilization_ratio > 0.75 THEN 8
          ELSE 0 END) +
    (CASE WHEN kyc_risk_category = 'HIGH' THEN 10
          WHEN kyc_risk_category = 'MEDIUM' THEN 5
          ELSE 0 END) +
    (CASE WHEN is_pep = 1 THEN 5 ELSE 0 END) +
    (CASE WHEN is_restructured = 1 THEN 5 ELSE 0 END)
    AS ews_composite_score
FROM v_account_risk_base
ORDER BY ews_composite_score DESC
LIMIT 25;

# 6.3 Bucket accounts into EWS risk tiers from the composite score, with counts and total exposure per tier
WITH scored AS (
    SELECT
        account_id, disbursed_amount, overdue_amount,
        (CASE
            WHEN sma_category = 'NPA' THEN 40
            WHEN sma_category = 'SMA-2' THEN 25
            WHEN sma_category = 'SMA-1' THEN 15
            WHEN sma_category = 'SMA-0' THEN 5
            ELSE 0 END) +
        (CASE WHEN emi_bounced = 1 THEN 15 ELSE 0 END) +
        (CASE WHEN min_due_paid = 0 THEN 10 ELSE 0 END) +
        (CASE WHEN credit_utilization_ratio > 0.9 THEN 15
              WHEN credit_utilization_ratio > 0.75 THEN 8
              ELSE 0 END) +
        (CASE WHEN kyc_risk_category = 'HIGH' THEN 10
              WHEN kyc_risk_category = 'MEDIUM' THEN 5
              ELSE 0 END) +
        (CASE WHEN is_pep = 1 THEN 5 ELSE 0 END) +
        (CASE WHEN is_restructured = 1 THEN 5 ELSE 0 END) AS score
    FROM v_account_risk_base
)
SELECT
    CASE
        WHEN score >= 60 THEN 'CRITICAL'
        WHEN score >= 40 THEN 'HIGH'
        WHEN score >= 20 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS ews_tier,
    COUNT(*) AS n_accounts,
    ROUND(SUM(disbursed_amount),2) AS total_exposure,
    ROUND(SUM(overdue_amount),2) AS total_overdue
FROM scored
GROUP BY ews_tier
ORDER BY MIN(score) DESC;

# 6.4 Cross-check: accounts scored CRITICAL by the composite score that do
--     NOT yet have an open alert — a coverage gap in the alerting system
WITH scored AS (
    SELECT
        b.account_key, b.account_id,
        (CASE
            WHEN sma_category = 'NPA' THEN 40
            WHEN sma_category = 'SMA-2' THEN 25
            WHEN sma_category = 'SMA-1' THEN 15
            WHEN sma_category = 'SMA-0' THEN 5
            ELSE 0 END) +
        (CASE WHEN emi_bounced = 1 THEN 15 ELSE 0 END) +
        (CASE WHEN min_due_paid = 0 THEN 10 ELSE 0 END) AS score
    FROM v_account_risk_base b
)
SELECT s.account_id, s.score
FROM scored s
WHERE s.score >= 60
  AND NOT EXISTS (
      SELECT 1 FROM v_alert al
      WHERE al.entity_type = 'Account' AND al.entity_key = s.account_key
        AND al.alert_status NOT IN ('Closed','False-Positive')
  )
ORDER BY s.score DESC;

# SECTION 7 — FRAUD & TRANSACTION MONITORING

# 7.1 Fraud rate by channel (which channel is the weakest control point)
SELECT channel,
       COUNT(*) AS n_txns,
       SUM(CASE WHEN is_flagged_fraud = 1 THEN 1 ELSE 0 END) AS n_flagged,
       ROUND(100.0 * SUM(CASE WHEN is_flagged_fraud = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS fraud_rate_pct
FROM v_txn
GROUP BY channel
ORDER BY fraud_rate_pct DESC;

# 7.2 Accounts with unusually high average fraud_score across their
--     transactions (behavioral outlier detection, simple z-score approach)
WITH acct_stats AS (
    SELECT account_key, AVG(fraud_score) AS avg_score, COUNT(*) AS n_txns
    FROM v_txn
    WHERE fraud_score IS NOT NULL
    GROUP BY account_key
    HAVING n_txns >= 3
),
overall AS (
    SELECT AVG(fraud_score) AS pop_mean,
           (SELECT AVG((fraud_score - (SELECT AVG(fraud_score) FROM v_txn))
                        * (fraud_score - (SELECT AVG(fraud_score) FROM v_txn)))
            FROM v_txn) AS pop_var
    FROM v_txn
)
SELECT a.account_key, ROUND(a.avg_score,3) AS avg_fraud_score, a.n_txns,
       ROUND((a.avg_score - o.pop_mean) / SQRT(o.pop_var), 2) AS z_score
FROM acct_stats a
CROSS JOIN overall o
WHERE (a.avg_score - o.pop_mean) / SQRT(o.pop_var) > 1.5
ORDER BY z_score DESC
LIMIT 20;

# 7.3 Same-day multiple high-value transactions per account (velocity check
--     — a classic transaction-monitoring EWS rule)
SELECT account_key, substr(transaction_timestamp,1,10) AS txn_day,
       COUNT(*) AS n_txns, ROUND(SUM(amount),2) AS total_amount
FROM v_txn
WHERE amount > 20000
GROUP BY account_key, txn_day
HAVING n_txns >= 3
ORDER BY total_amount DESC
LIMIT 20;

# 7.4 Reversed/failed transaction ratio per account (operational risk / possible fraud-testing pattern)
SELECT account_key,
       COUNT(*) AS total_txns,
       SUM(CASE WHEN status IN ('REVERSED','FAILED') THEN 1 ELSE 0 END) AS reversed_or_failed,
       ROUND(100.0*SUM(CASE WHEN status IN ('REVERSED','FAILED') THEN 1 ELSE 0 END)/COUNT(*),1) AS pct
FROM v_txn
GROUP BY account_key
HAVING total_txns >= 5
ORDER BY pct DESC
LIMIT 20;

# SECTION 8 — ALERT MANAGEMENT & SLA ANALYTICS

# 8.1 Alert volume and false-positive rate by severity
SELECT severity,
       COUNT(*) AS total_alerts,
       SUM(CASE WHEN alert_status = 'False-Positive' THEN 1 ELSE 0 END) AS false_positives,
       ROUND(100.0*SUM(CASE WHEN alert_status='False-Positive' THEN 1 ELSE 0 END)/COUNT(*),1) AS fp_rate_pct
FROM v_alert
GROUP BY severity
ORDER BY fp_rate_pct DESC;
 
# 8.2 Alert backlog per assigned analyst/RM (workload distribution)
SELECT assigned_to,
       COUNT(*) AS open_alerts
FROM v_alert
WHERE alert_status NOT IN ('Closed','False-Positive')
GROUP BY assigned_to
ORDER BY open_alerts DESC;

# 8.3 Risk domains generating the most CRITICAL alerts (where to focus model tuning / analyst attention)
SELECT rs.risk_domain, COUNT(*) AS critical_alerts
FROM v_alert al
JOIN v_risk rs ON al.score_id = rs.score_id
WHERE al.severity = 'CRITICAL'
GROUP BY rs.risk_domain
ORDER BY critical_alerts DESC;

# SECTION 9 — PORTFOLIO-LEVEL RISK SUMMARY

# 9.1 Portfolio quality snapshot by product: exposure, NPA%, provisioning
WITH latest_perf AS (
    SELECT f.*, ROW_NUMBER() OVER (PARTITION BY account_key ORDER BY fact_id DESC) AS rn
    FROM v_perf f
)
SELECT p.product_name,
       COUNT(DISTINCT a.account_key) AS n_accounts,
       ROUND(SUM(a.disbursed_amount),2) AS total_exposure,
       SUM(CASE WHEN lp.sma_category='NPA' THEN 1 ELSE 0 END) AS npa_accounts,
       ROUND(100.0*SUM(CASE WHEN lp.sma_category='NPA' THEN 1 ELSE 0 END)/COUNT(DISTINCT a.account_key),2) AS npa_pct,
       ROUND(SUM(lp.provision_amount),2) AS total_provision
FROM latest_perf lp
JOIN v_account a ON lp.account_key = a.account_key
JOIN dim_product p ON a.product_key = p.product_key
WHERE lp.rn = 1
GROUP BY p.product_name
ORDER BY npa_pct DESC;

# 9.2 One-row-per-account master risk view combining composite EWS score,
--     latest risk_score entries across all domains, and open alert count
--     -- the table a risk dashboard would page through
WITH latest_perf AS (
    SELECT f.*, ROW_NUMBER() OVER (PARTITION BY account_key ORDER BY fact_id DESC) AS rn
    FROM v_perf f
),
scored AS (
    SELECT
        a.account_key, a.account_id, c.customer_name,
        lp.sma_category, lp.dpd_days, lp.overdue_amount,
        (CASE
            WHEN lp.sma_category = 'NPA' THEN 40
            WHEN lp.sma_category = 'SMA-2' THEN 25
            WHEN lp.sma_category = 'SMA-1' THEN 15
            WHEN lp.sma_category = 'SMA-0' THEN 5
            ELSE 0 END) +
        (CASE WHEN lp.emi_bounced = 1 THEN 15 ELSE 0 END) +
        (CASE WHEN lp.min_due_paid = 0 THEN 10 ELSE 0 END) AS composite_score
    FROM latest_perf lp
    JOIN v_account a ON lp.account_key = a.account_key
    JOIN v_customer c ON lp.customer_key = c.customer_key
    WHERE lp.rn = 1
),
domain_scores AS (
    SELECT entity_key,
           MAX(CASE WHEN risk_domain='CREDIT' THEN risk_band END) AS credit_band,
           MAX(CASE WHEN risk_domain='MARKET' THEN risk_band END) AS market_band,
           MAX(CASE WHEN risk_domain='LIQUIDITY' THEN risk_band END) AS liquidity_band,
           MAX(CASE WHEN risk_domain='FRAUD' THEN risk_band END) AS fraud_band
    FROM v_risk
    WHERE entity_type = 'Account'
    GROUP BY entity_key
),
alert_counts AS (
    SELECT entity_key, COUNT(*) AS open_alerts
    FROM v_alert
    WHERE entity_type='Account' AND alert_status NOT IN ('Closed','False-Positive')
    GROUP BY entity_key
)
SELECT
    s.account_id, s.customer_name, s.sma_category, s.dpd_days,
    s.composite_score,
    d.credit_band, d.market_band, d.liquidity_band, d.fraud_band,
    COALESCE(ac.open_alerts,0) AS open_alerts
FROM scored s
LEFT JOIN domain_scores d ON s.account_key = d.entity_key
LEFT JOIN alert_counts ac ON s.account_key = ac.entity_key
ORDER BY s.composite_score DESC, open_alerts DESC
LIMIT 30;
 
