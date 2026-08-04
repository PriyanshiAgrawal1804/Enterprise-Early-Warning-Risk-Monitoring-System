"""
02_feature_engineering.py
--------------------------
Enterprise Early Warning Risk Monitoring System (EWRMS)

Phase 1: Feature Engineering
Derives the risk-analysis variables used throughout EDA, K-Means
segmentation, and the predictive default model:
  - credit_history_months
  - dti_ratio (Debt-to-Income)
  - lti_ratio (Loan-to-Income)
  - fico_bucket
  - loan_status_group ('Good' / 'Bad')
  - cost_to_income proxy, liquidity proxy (for CAMEL-style KPIs)

Input:  outputs/processed_data/loan_data_clean.csv
Output: outputs/processed_data/loan_data_features.csv
"""

import pandas as pd
import numpy as np

IN_PATH = "outputs/processed_data/loan_data_clean.csv"
OUT_PATH = "outputs/processed_data/loan_data_features.csv"


def add_credit_history(df: pd.DataFrame) -> pd.DataFrame:
    df["issue_date"] = pd.to_datetime(df["issue_date"])
    df["earliest_credit_line"] = pd.to_datetime(df["earliest_credit_line"])
    days_diff = (df["issue_date"] - df["earliest_credit_line"]).dt.days
    df["credit_history_months"] = (days_diff / 30.44).round().astype(int)
    return df


def add_financial_ratios(df: pd.DataFrame) -> pd.DataFrame:
    monthly_income = df["annual_income"] / 12
    df["dti_ratio"] = (df["monthly_installment"] / monthly_income).round(4)
    df["lti_ratio"] = (df["loan_amount"] / df["annual_income"]).round(4)
    return df


def add_fico_bucket(df: pd.DataFrame) -> pd.DataFrame:
    bins = [0, 580, 670, 740, 800, 850]
    labels = ["Poor", "Fair", "Good", "Very Good", "Excellent"]
    df["fico_bucket"] = pd.cut(df["fico_score"], bins=bins, labels=labels, include_lowest=True)
    return df


def add_loan_status_group(df: pd.DataFrame) -> pd.DataFrame:
    good = ["Fully Paid", "Current"]
    df["loan_status_group"] = np.where(df["loan_status"].isin(good), "Good", "Bad")
    df["default_flag"] = (df["loan_status_group"] == "Bad").astype(int)
    return df


def add_camel_style_proxies(df: pd.DataFrame) -> pd.DataFrame:
    # Proxies built from account-level data to roll up into CAMEL-style
    # portfolio KPIs (Capital, Asset quality, Management, Earnings, Liquidity)
    df["liquidity_proxy"] = 1 - df["revolving_utilization_pct"] / 100
    df["cost_to_income_proxy"] = (df["interest_rate"] / 100) * 0.35  # simplified operational cost ratio proxy
    return df


def main():
    df = pd.read_csv(IN_PATH)
    df = add_credit_history(df)
    df = add_financial_ratios(df)
    df = add_fico_bucket(df)
    df = add_loan_status_group(df)
    df = add_camel_style_proxies(df)

    df.to_csv(OUT_PATH, index=False)
    print(f"Saved engineered feature set -> {OUT_PATH} ({df.shape[0]} rows, {df.shape[1]} cols)")
    print("\nSample of key engineered features:")
    print(df[["loan_id", "credit_history_months", "dti_ratio", "lti_ratio",
               "fico_bucket", "loan_status_group"]].head())


if __name__ == "__main__":
    main()
