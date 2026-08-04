"""
05_predictive_model.py
-----------------------
Enterprise Early Warning Risk Monitoring System (EWRMS)

Phase 2: Predictive Modeling
Trains supervised models to predict Probability of Default (PD):
  - Logistic Regression (interpretable baseline / regulatory-friendly)
  - Gradient Boosted Trees (GradientBoostingClassifier)

NOTE ON XGBoost: this sandbox has no internet access to install the
`xgboost` package, so GradientBoostingClassifier (scikit-learn) is
used as a drop-in stand-in — it is the same gradient-boosted-tree
family. To use real XGBoost in your own environment, simply:
    pip install xgboost
    from xgboost import XGBClassifier
    model = XGBClassifier(n_estimators=300, max_depth=4, learning_rate=0.05)
and swap it into `train_models()` below — the rest of the pipeline
(scoring, evaluation, export) is unchanged.

Input:  outputs/processed_data/loan_data_segmented.csv
Output: outputs/processed_data/loan_data_with_risk_scores.csv
        outputs/images/09_roc_curve.png
        outputs/images/10_feature_importance.png
        outputs/images/11_confusion_matrix.png
"""

import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import seaborn as sns

from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.metrics import (roc_auc_score, roc_curve, confusion_matrix,
                              classification_report)

IN_PATH = "outputs/processed_data/loan_data_segmented.csv"
OUT_PATH = "outputs/processed_data/loan_data_with_risk_scores.csv"
IMG_DIR = "outputs/images"

FEATURES = [
    "age", "loan_amount", "term_months", "interest_rate", "annual_income",
    "fico_score", "num_delinquencies_2yrs", "open_credit_lines",
    "revolving_utilization_pct", "overdraft_count_6m", "cashflow_volatility_score",
    "dti_ratio", "lti_ratio", "credit_history_months",
]
TARGET = "default_flag"


def train_models(X_train, y_train):
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)

    log_reg = LogisticRegression(max_iter=1000, class_weight="balanced")
    log_reg.fit(X_train_scaled, y_train)

    gbm = GradientBoostingClassifier(n_estimators=300, max_depth=3,
                                      learning_rate=0.05, random_state=42)
    gbm.fit(X_train, y_train)  # tree model does not need scaling

    return log_reg, gbm, scaler


def evaluate(name, y_test, y_prob):
    auc = roc_auc_score(y_test, y_prob)
    print(f"\n--- {name} ---")
    print(f"ROC-AUC: {auc:.4f}")
    print(classification_report(y_test, (y_prob > 0.5).astype(int)))
    return auc


def plot_roc(y_test, probs_dict):
    plt.figure(figsize=(7, 6))
    colors = {"Logistic Regression": "#2980b9", "Gradient Boosted Trees": "#c0392b"}
    for name, y_prob in probs_dict.items():
        fpr, tpr, _ = roc_curve(y_test, y_prob)
        auc = roc_auc_score(y_test, y_prob)
        plt.plot(fpr, tpr, label=f"{name} (AUC={auc:.3f})", color=colors.get(name), linewidth=2)
    plt.plot([0, 1], [0, 1], linestyle="--", color="gray")
    plt.title("ROC Curve — Probability of Default Models", fontsize=13, weight="bold")
    plt.xlabel("False Positive Rate")
    plt.ylabel("True Positive Rate")
    plt.legend()
    plt.tight_layout()
    plt.savefig(f"{IMG_DIR}/09_roc_curve.png", dpi=150)
    plt.close()


def plot_feature_importance(gbm, feature_names):
    importances = pd.Series(gbm.feature_importances_, index=feature_names).sort_values(ascending=True)
    plt.figure(figsize=(8, 6))
    importances.plot(kind="barh", color="#16a085")
    plt.title("Feature Importance — Default Prediction Model (GBM)", fontsize=13, weight="bold")
    plt.xlabel("Relative Importance")
    plt.tight_layout()
    plt.savefig(f"{IMG_DIR}/10_feature_importance.png", dpi=150)
    plt.close()


def plot_confusion(y_test, y_pred):
    cm = confusion_matrix(y_test, y_pred)
    plt.figure(figsize=(6, 5))
    sns.heatmap(cm, annot=True, fmt="d", cmap="Blues",
                xticklabels=["Good", "Bad"], yticklabels=["Good", "Bad"])
    plt.title("Confusion Matrix — GBM Default Classifier", fontsize=13, weight="bold")
    plt.ylabel("Actual")
    plt.xlabel("Predicted")
    plt.tight_layout()
    plt.savefig(f"{IMG_DIR}/11_confusion_matrix.png", dpi=150)
    plt.close()


def main():
    df = pd.read_csv(IN_PATH)
    df = df.dropna(subset=FEATURES + [TARGET])

    X = df[FEATURES]
    y = df[TARGET]

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.25, random_state=42, stratify=y
    )

    log_reg, gbm, scaler = train_models(X_train, y_train)

    X_test_scaled = scaler.transform(X_test)
    y_prob_lr = log_reg.predict_proba(X_test_scaled)[:, 1]
    y_prob_gbm = gbm.predict_proba(X_test)[:, 1]

    evaluate("Logistic Regression", y_test, y_prob_lr)
    auc_gbm = evaluate("Gradient Boosted Trees", y_test, y_prob_gbm)

    plot_roc(y_test, {"Logistic Regression": y_prob_lr, "Gradient Boosted Trees": y_prob_gbm})
    plot_feature_importance(gbm, FEATURES)
    plot_confusion(y_test, (y_prob_gbm > 0.5).astype(int))

    # Score the FULL portfolio (0-100 risk score) using the GBM model -> real-time scoring engine
    full_scaled = X  # tree model uses raw features
    df["risk_score"] = (gbm.predict_proba(df[FEATURES])[:, 1] * 100).round(1)
    df["risk_score_band"] = pd.cut(
        df["risk_score"], bins=[-1, 20, 40, 60, 80, 101],
        labels=["Very Low", "Low", "Moderate", "High", "Critical"]
    )

    df.to_csv(OUT_PATH, index=False)
    print(f"\nFinal AUC (GBM, used as the production scoring engine): {auc_gbm:.4f}")
    print(f"Saved risk-scored portfolio -> {OUT_PATH}")
    print("\nRisk score band distribution:\n", df["risk_score_band"].value_counts())


if __name__ == "__main__":
    main()
