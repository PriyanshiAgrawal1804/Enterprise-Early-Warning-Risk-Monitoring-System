"""
03_eda.py
---------
Enterprise Early Warning Risk Monitoring System (EWRMS)

Phase 2: Exploratory Data Analysis
Univariate, bivariate, and multivariate analysis of the loan
portfolio to understand distributions, correlations, and risk
trends before modeling.

Input:  outputs/processed_data/loan_data_features.csv
Output: outputs/images/*.png
"""

import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import seaborn as sns

sns.set_theme(style="whitegrid", palette="deep")
IN_PATH = "outputs/processed_data/loan_data_features.csv"
IMG_DIR = "outputs/images"


def plot_default_rate_by_region(df):
    rate = df.groupby("region")["default_flag"].mean().sort_values(ascending=False) * 100
    plt.figure(figsize=(8, 5))
    ax = sns.barplot(x=rate.index, y=rate.values, color="#c0392b")
    ax.set_title("Bad Loan (Charge-Off/Default) Rate by Region", fontsize=13, weight="bold")
    ax.set_ylabel("Bad Loan Rate (%)")
    ax.set_xlabel("Region")
    for i, v in enumerate(rate.values):
        ax.text(i, v + 0.3, f"{v:.1f}%", ha="center", fontsize=9)
    plt.tight_layout()
    plt.savefig(f"{IMG_DIR}/01_default_rate_by_region.png", dpi=150)
    plt.close()


def plot_fico_distribution(df):
    plt.figure(figsize=(8, 5))
    sns.histplot(df["fico_score"], bins=30, kde=True, color="#2c3e50")
    plt.title("FICO Score Distribution Across Portfolio", fontsize=13, weight="bold")
    plt.xlabel("FICO Score")
    plt.tight_layout()
    plt.savefig(f"{IMG_DIR}/02_fico_score_distribution.png", dpi=150)
    plt.close()


def plot_dti_vs_default(df):
    plt.figure(figsize=(8, 5))
    sample = df.sample(min(2000, len(df)), random_state=1)
    sns.boxplot(x="loan_status_group", y="dti_ratio", data=sample, palette=["#27ae60", "#c0392b"])
    plt.title("Debt-to-Income Ratio: Good vs Bad Loans", fontsize=13, weight="bold")
    plt.ylabel("DTI Ratio")
    plt.xlabel("Loan Status Group")
    plt.ylim(0, 1.5)
    plt.tight_layout()
    plt.savefig(f"{IMG_DIR}/03_dti_vs_loan_status.png", dpi=150)
    plt.close()


def plot_correlation_heatmap(df):
    cols = ["age", "loan_amount", "interest_rate", "annual_income", "fico_score",
            "num_delinquencies_2yrs", "revolving_utilization_pct", "overdraft_count_6m",
            "dti_ratio", "lti_ratio", "credit_history_months", "default_flag"]
    corr = df[cols].corr()
    plt.figure(figsize=(10, 8))
    sns.heatmap(corr, annot=True, fmt=".2f", cmap="RdBu_r", center=0, square=True,
                cbar_kws={"shrink": 0.8})
    plt.title("Correlation Matrix of Key Risk Drivers", fontsize=13, weight="bold")
    plt.tight_layout()
    plt.savefig(f"{IMG_DIR}/04_correlation_heatmap.png", dpi=150)
    plt.close()


def plot_loan_purpose_breakdown(df):
    plt.figure(figsize=(8, 5))
    order = df["loan_purpose"].value_counts().index
    ax = sns.countplot(y="loan_purpose", data=df, order=order, hue="loan_status_group",
                        palette={"Good": "#27ae60", "Bad": "#c0392b"})
    ax.set_title("Loan Volume by Purpose, Split by Status", fontsize=13, weight="bold")
    ax.set_xlabel("Number of Loans")
    ax.set_ylabel("Loan Purpose")
    plt.tight_layout()
    plt.savefig(f"{IMG_DIR}/05_loan_purpose_breakdown.png", dpi=150)
    plt.close()


def plot_monthly_bad_loan_trend(df):
    df["issue_month"] = pd.to_datetime(df["issue_date"]).dt.to_period("M").dt.to_timestamp()
    trend = df.groupby("issue_month")["default_flag"].mean() * 100
    plt.figure(figsize=(9, 5))
    plt.plot(trend.index, trend.values, marker="o", color="#8e44ad", linewidth=2)
    plt.title("Monthly Bad Loan Rate Trend (Early Warning Signal)", fontsize=13, weight="bold")
    plt.ylabel("Bad Loan Rate (%)")
    plt.xlabel("Loan Issue Month")
    plt.xticks(rotation=45)
    plt.tight_layout()
    plt.savefig(f"{IMG_DIR}/06_monthly_bad_loan_trend.png", dpi=150)
    plt.close()


def main():
    df = pd.read_csv(IN_PATH)
    plot_default_rate_by_region(df)
    plot_fico_distribution(df)
    plot_dti_vs_default(df)
    plot_correlation_heatmap(df)
    plot_loan_purpose_breakdown(df)
    plot_monthly_bad_loan_trend(df)
    print("EDA charts saved to outputs/images/")


if __name__ == "__main__":
    main()
