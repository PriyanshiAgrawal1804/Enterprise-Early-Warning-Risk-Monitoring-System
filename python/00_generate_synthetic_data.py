"""
00_generate_synthetic_data.py
------------------------------
Enterprise Early Warning Risk Monitoring System (EWRMS)

Generates a realistic SYNTHETIC bank loan portfolio dataset for
demonstration purposes (no real customer data is used anywhere in
this project). The schema mirrors what a real core-banking / LOS
(Loan Origination System) extract would look like.

Output: data/loan_data_raw.csv
"""

import numpy as np
import pandas as pd
from datetime import datetime, timedelta

np.random.seed(42)

N = 8000  # number of loan accounts

# ------------------------------------------------------------------
# 1. Core identifiers
# ------------------------------------------------------------------
loan_id = [f"LN{100000 + i}" for i in range(N)]
customer_id = [f"CUST{20000 + i}" for i in range(N)]

# ------------------------------------------------------------------
# 2. Demographics
# ------------------------------------------------------------------
age = np.random.normal(40, 11, N).clip(21, 70).astype(int)
gender = np.random.choice(["Male", "Female"], N, p=[0.58, 0.42])
region = np.random.choice(
    ["North", "South", "East", "West", "Central"], N,
    p=[0.22, 0.24, 0.18, 0.20, 0.16]
)
employment_type = np.random.choice(
    ["Salaried", "Self-Employed", "Business Owner", "Retired"], N,
    p=[0.55, 0.25, 0.15, 0.05]
)

# ------------------------------------------------------------------
# 3. Loan details
# ------------------------------------------------------------------
loan_purpose = np.random.choice(
    ["Home", "Auto", "Personal", "Education", "Business", "Credit Card Refinance"],
    N, p=[0.22, 0.18, 0.25, 0.10, 0.15, 0.10]
)
loan_amount = np.round(np.random.lognormal(mean=10.2, sigma=0.7, size=N), -2).clip(50000, 5000000)
term_months = np.random.choice([12, 24, 36, 48, 60, 84, 120, 180, 240], N,
                                p=[0.10, 0.12, 0.18, 0.15, 0.15, 0.10, 0.10, 0.06, 0.04])
interest_rate = np.round(np.random.normal(11.5, 3.2, N).clip(6.5, 24.0), 2)

annual_income = np.round(np.random.lognormal(mean=13.0, sigma=0.55, size=N), -2).clip(150000, 8000000)
monthly_income = annual_income / 12

# Earliest credit line & issue date -> credit history length
today = datetime(2026, 7, 1)
issue_date = [today - timedelta(days=int(np.random.uniform(30, 1800))) for _ in range(N)]
earliest_credit_line = [
    issue_date[i] - timedelta(days=int(np.random.uniform(365 * 1, 365 * 20)))
    for i in range(N)
]

# ------------------------------------------------------------------
# 4. Credit bureau / behavioral fields
# ------------------------------------------------------------------
fico_score = np.random.normal(680, 65, N).clip(300, 850).astype(int)
num_delinquencies_2yrs = np.random.poisson(0.4, N)
open_credit_lines = np.random.poisson(5, N).clip(0, 25)
revolving_utilization = np.random.beta(2, 3, N) * 100
overdraft_count_6m = np.random.poisson(0.8, N)
avg_monthly_cashflow_volatility = np.round(np.random.gamma(2, 1500, N), 2)

# ------------------------------------------------------------------
# 5. Repayment / installment
# ------------------------------------------------------------------
monthly_installment = np.round(
    (loan_amount * (interest_rate / 1200)) /
    (1 - (1 + interest_rate / 1200) ** (-term_months)), 2
)

# ------------------------------------------------------------------
# 6. Employee / internal activity fields (operational risk monitoring)
# ------------------------------------------------------------------
handled_by_employee_id = np.random.choice([f"EMP{1000+i}" for i in range(120)], N)
off_hours_access_flag = np.random.choice([0, 1], N, p=[0.94, 0.06])
bulk_download_flag = np.random.choice([0, 1], N, p=[0.97, 0.03])

# ------------------------------------------------------------------
# 7. Simulate loan status as a function of risk drivers (for a
#    realistic, learnable relationship -> used later for modeling)
# ------------------------------------------------------------------
dti_raw = (monthly_installment / monthly_income).clip(0, 2)
risk_logit = (
    -6.5
    + 4.5 * dti_raw
    - 0.010 * (fico_score - 650)
    + 0.35 * num_delinquencies_2yrs
    + 0.02 * revolving_utilization
    + 0.30 * overdraft_count_6m
    + 0.00025 * avg_monthly_cashflow_volatility
    + 0.15 * off_hours_access_flag
)
prob_default = 1 / (1 + np.exp(-risk_logit))
default_flag = np.random.binomial(1, prob_default.clip(0.01, 0.9))

loan_status = np.where(
    default_flag == 1,
    np.random.choice(["Charged Off", "Default"], N, p=[0.7, 0.3]),
    np.random.choice(["Fully Paid", "Current"], N, p=[0.35, 0.65])
)

df = pd.DataFrame({
    "loan_id": loan_id,
    "customer_id": customer_id,
    "age": age,
    "gender": gender,
    "region": region,
    "employment_type": employment_type,
    "loan_purpose": loan_purpose,
    "loan_amount": loan_amount,
    "term_months": term_months,
    "interest_rate": interest_rate,
    "annual_income": annual_income,
    "issue_date": [d.strftime("%Y-%m-%d") for d in issue_date],
    "earliest_credit_line": [d.strftime("%Y-%m-%d") for d in earliest_credit_line],
    "fico_score": fico_score,
    "num_delinquencies_2yrs": num_delinquencies_2yrs,
    "open_credit_lines": open_credit_lines,
    "revolving_utilization_pct": np.round(revolving_utilization, 2),
    "overdraft_count_6m": overdraft_count_6m,
    "cashflow_volatility_score": avg_monthly_cashflow_volatility,
    "monthly_installment": monthly_installment,
    "handled_by_employee_id": handled_by_employee_id,
    "off_hours_access_flag": off_hours_access_flag,
    "bulk_download_flag": bulk_download_flag,
    "loan_status": loan_status,
})

# Inject some realistic messiness for the cleaning script to handle
mask_missing_income = np.random.choice([True, False], N, p=[0.02, 0.98])
df.loc[mask_missing_income, "annual_income"] = np.nan

mask_missing_fico = np.random.choice([True, False], N, p=[0.015, 0.985])
df.loc[mask_missing_fico, "fico_score"] = np.nan

dup_rows = df.sample(40, random_state=1)
df = pd.concat([df, dup_rows], ignore_index=True)

df.to_csv("/home/claude/EWRMS/data/loan_data_raw.csv", index=False)
print(f"Generated {len(df)} rows -> data/loan_data_raw.csv")
