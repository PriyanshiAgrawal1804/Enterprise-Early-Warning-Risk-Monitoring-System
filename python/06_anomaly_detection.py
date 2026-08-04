"""
06_anomaly_detection.py
------------------------
Enterprise Early Warning Risk Monitoring System (EWRMS)

Phase 2: Advanced Detection (Operational & Fraud Risk)
Uses Isolation Forest to flag suspicious transactions / employee
behavior — e.g., off-hours system access, bulk data downloads,
and abnormal cash-flow volatility — that traditional rule-based
monitoring would miss.

Input:  outputs/processed_data/loan_data_with_risk_scores.csv
Output: outputs/processed_data/employee_activity_flagged.csv
        outputs/images/12_anomaly_detection_scatter.png
"""

import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler

IN_PATH = "outputs/processed_data/loan_data_with_risk_scores.csv"
OUT_PATH = "outputs/processed_data/employee_activity_flagged.csv"
IMG_DIR = "outputs/images"

ANOMALY_FEATURES = [
    "off_hours_access_flag", "bulk_download_flag",
    "cashflow_volatility_score", "overdraft_count_6m",
]


def main():
    df = pd.read_csv(IN_PATH)

    activity = df.groupby("handled_by_employee_id").agg(
        num_loans_handled=("loan_id", "count"),
        off_hours_access_events=("off_hours_access_flag", "sum"),
        bulk_download_events=("bulk_download_flag", "sum"),
        avg_cashflow_volatility=("cashflow_volatility_score", "mean"),
        avg_overdraft_count=("overdraft_count_6m", "mean"),
        bad_loans_handled=("default_flag", "sum"),
    ).reset_index()

    X = activity[["off_hours_access_events", "bulk_download_events",
                   "avg_cashflow_volatility", "avg_overdraft_count",
                   "bad_loans_handled"]]

    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    iso_forest = IsolationForest(n_estimators=300, contamination=0.07, random_state=42)
    activity["anomaly_flag"] = iso_forest.fit_predict(X_scaled)
    activity["anomaly_flag"] = activity["anomaly_flag"].map({1: 0, -1: 1})  # 1 = anomalous
    activity["anomaly_score"] = -iso_forest.score_samples(X_scaled)  # higher = more anomalous

    flagged = activity[activity["anomaly_flag"] == 1].sort_values("anomaly_score", ascending=False)
    print(f"Flagged {len(flagged)} of {len(activity)} employees as anomalous "
          f"({100*len(flagged)/len(activity):.1f}%)")
    print("\nTop flagged employees:\n", flagged.head(10).to_string(index=False))

    # Visualize: bulk downloads vs off-hours access, colored by anomaly flag
    plt.figure(figsize=(8, 6))
    colors = activity["anomaly_flag"].map({0: "#2980b9", 1: "#c0392b"})
    plt.scatter(activity["off_hours_access_events"], activity["bulk_download_events"],
                c=colors, s=60, alpha=0.7, edgecolor="k", linewidth=0.3)
    plt.title("Isolation Forest — Employee Activity Anomaly Detection", fontsize=13, weight="bold")
    plt.xlabel("Off-Hours Access Events")
    plt.ylabel("Bulk Download Events")
    handles = [plt.Line2D([0], [0], marker="o", color="w", markerfacecolor=c, markersize=9, label=l)
               for c, l in [("#2980b9", "Normal"), ("#c0392b", "Anomalous")]]
    plt.legend(handles=handles)
    plt.tight_layout()
    plt.savefig(f"{IMG_DIR}/12_anomaly_detection_scatter.png", dpi=150)
    plt.close()

    activity.to_csv(OUT_PATH, index=False)
    print(f"\nSaved employee activity anomaly report -> {OUT_PATH}")


if __name__ == "__main__":
    main()
