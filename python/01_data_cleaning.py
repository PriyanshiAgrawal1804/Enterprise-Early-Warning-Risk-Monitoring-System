"""
01_data_cleaning.py
--------------------
Enterprise Early Warning Risk Monitoring System (EWRMS)

Phase 1: Data Engineering and Preparation
Cleans the raw loan portfolio extract:
  - handles missing values
  - removes duplicate records
  - standardizes data formats / dtypes

Input:  data/loan_data_raw.csv
Output: outputs/processed_data/loan_data_clean.csv
"""

import pandas as pd
import numpy as np

RAW_PATH = "data/loan_data_raw.csv"
OUT_PATH = "outputs/processed_data/loan_data_clean.csv"


def load_data(path: str) -> pd.DataFrame:
    df = pd.read_csv(path, parse_dates=["issue_date", "earliest_credit_line"])
    return df


def remove_duplicates(df: pd.DataFrame) -> pd.DataFrame:
    before = len(df)
    df = df.drop_duplicates(subset="loan_id", keep="first")
    print(f"Removed {before - len(df)} duplicate loan_id rows")
    return df


def impute_missing(df: pd.DataFrame) -> pd.DataFrame:
    # Income: impute with the median income for the same employment_type + region cohort
    df["annual_income"] = df.groupby(["employment_type", "region"])["annual_income"] \
        .transform(lambda s: s.fillna(s.median()))
    df["annual_income"] = df["annual_income"].fillna(df["annual_income"].median())

    # FICO: impute with overall median (a conservative, non-optimistic choice)
    df["fico_score"] = df["fico_score"].fillna(df["fico_score"].median())

    missing_report = df.isna().sum()
    missing_report = missing_report[missing_report > 0]
    print("Remaining missing values after imputation:\n", missing_report if len(missing_report) else "None")
    return df


def standardize_formats(df: pd.DataFrame) -> pd.DataFrame:
    df["gender"] = df["gender"].str.title().str.strip()
    df["region"] = df["region"].str.title().str.strip()
    df["employment_type"] = df["employment_type"].str.strip()
    df["loan_purpose"] = df["loan_purpose"].str.strip()
    df["fico_score"] = df["fico_score"].round().astype(int)
    df["loan_amount"] = df["loan_amount"].round(2)
    return df


def main():
    df = load_data(RAW_PATH)
    print(f"Loaded raw dataset: {df.shape[0]} rows, {df.shape[1]} columns")

    df = remove_duplicates(df)
    df = impute_missing(df)
    df = standardize_formats(df)

    df.to_csv(OUT_PATH, index=False)
    print(f"Saved cleaned dataset -> {OUT_PATH} ({df.shape[0]} rows)")


if __name__ == "__main__":
    main()
