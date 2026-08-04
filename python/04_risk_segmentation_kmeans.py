"""
04_risk_segmentation_kmeans.py
-------------------------------
Enterprise Early Warning Risk Monitoring System (EWRMS)

Phase 2: Risk Segmentation (Unsupervised Learning)
Uses K-Means clustering on CAMEL-style indicators to group
customers into distinct risk states (e.g., Low-Risk, Watch-list,
Distressed). This mirrors regulatory CAMEL-based supervision
applied at the customer/account level.

Input:  outputs/processed_data/loan_data_features.csv
Output: outputs/processed_data/loan_data_segmented.csv
        outputs/images/07_risk_segments_scatter.png
        outputs/images/08_elbow_method.png
"""

import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import KMeans
from sklearn.decomposition import PCA

IN_PATH = "outputs/processed_data/loan_data_features.csv"
OUT_PATH = "outputs/processed_data/loan_data_segmented.csv"
IMG_DIR = "outputs/images"

FEATURES = [
    "dti_ratio", "lti_ratio", "revolving_utilization_pct",
    "liquidity_proxy", "cost_to_income_proxy", "num_delinquencies_2yrs",
    "overdraft_count_6m", "fico_score",
]


def find_optimal_k(X_scaled, k_range=range(2, 8)):
    inertias = []
    for k in k_range:
        km = KMeans(n_clusters=k, random_state=42, n_init=10)
        km.fit(X_scaled)
        inertias.append(km.inertia_)

    plt.figure(figsize=(7, 5))
    plt.plot(list(k_range), inertias, marker="o", color="#2980b9")
    plt.title("Elbow Method for Optimal K (Risk Segmentation)", fontsize=13, weight="bold")
    plt.xlabel("Number of Clusters (k)")
    plt.ylabel("Inertia")
    plt.tight_layout()
    plt.savefig(f"{IMG_DIR}/08_elbow_method.png", dpi=150)
    plt.close()


def main():
    df = pd.read_csv(IN_PATH)
    X = df[FEATURES].copy()

    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    find_optimal_k(X_scaled)

    k = 4
    kmeans = KMeans(n_clusters=k, random_state=42, n_init=10)
    df["cluster"] = kmeans.fit_predict(X_scaled)

    # Rank clusters by average default rate to assign meaningful labels
    cluster_default_rate = df.groupby("cluster")["default_flag"].mean().sort_values()
    ordered_clusters = cluster_default_rate.index.tolist()
    labels = ["Low-Risk", "Moderate-Risk", "Watch-list", "Distressed"][:k]
    cluster_map = {cluster_id: labels[i] for i, cluster_id in enumerate(ordered_clusters)}
    df["risk_segment"] = df["cluster"].map(cluster_map)

    # PCA for 2D visualization of the clusters
    pca = PCA(n_components=2)
    pca_coords = pca.fit_transform(X_scaled)
    df["pca_1"], df["pca_2"] = pca_coords[:, 0], pca_coords[:, 1]

    plt.figure(figsize=(8, 6))
    palette = {"Low-Risk": "#27ae60", "Moderate-Risk": "#f1c40f",
               "Watch-list": "#e67e22", "Distressed": "#c0392b"}
    sns.scatterplot(x="pca_1", y="pca_2", hue="risk_segment", data=df,
                     palette=palette, alpha=0.6, s=25)
    plt.title("Customer Risk Segments (K-Means on CAMEL Indicators, PCA View)",
              fontsize=12, weight="bold")
    plt.xlabel("Principal Component 1")
    plt.ylabel("Principal Component 2")
    plt.legend(title="Risk Segment")
    plt.tight_layout()
    plt.savefig(f"{IMG_DIR}/07_risk_segments_scatter.png", dpi=150)
    plt.close()

    summary = df.groupby("risk_segment").agg(
        num_customers=("loan_id", "count"),
        avg_default_rate=("default_flag", "mean"),
        avg_dti=("dti_ratio", "mean"),
        avg_fico=("fico_score", "mean"),
    ).round(3).sort_values("avg_default_rate", ascending=False)
    print("\nRisk Segment Summary:\n", summary)

    df.drop(columns=["cluster"]).to_csv(OUT_PATH, index=False)
    print(f"\nSaved segmented dataset -> {OUT_PATH}")


if __name__ == "__main__":
    main()
