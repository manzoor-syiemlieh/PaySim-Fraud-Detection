# Mobile-Money Fraud Detection (PaySim)

End-to-end fraud detection on 6.36M simulated mobile-money transactions, where fraud is only 0.13% of all activity (8,213 cases). The project pairs SQL transaction-monitoring analysis with a machine-learning pipeline that flags fraudulent `TRANSFER` and `CASH_OUT` transactions and decisively beats the dataset's built-in flagging rule.

## Overview

- **Problem:** detect rare fraudulent transactions (0.13% of data) in mobile-money transfers.
- **Baseline to beat:** the dataset's built-in rule (`isFlaggedFraud`) catches only 16 of 8,213 frauds — 0.19% recall.
- **Result:** XGBoost reaches **0.99 AUPRC** and catches **2,453 of 2,464** held-out frauds (99.6% recall, 92.4% precision).

## Dataset

[PaySim — Synthetic Financial Datasets for Fraud Detection (Kaggle)](https://www.kaggle.com/datasets/ealaxi/paysim1)

- 6,362,620 transactions over 744 simulation steps (30 days), 11 columns.
- Synthetic data modelled on real mobile-money logs from an African operator.
- **Not included in this repo** (~470 MB). Download it from Kaggle and update the file path in the notebook and the SQL load cell.

## Repository

| File | Description |
|------|-------------|
| `paysim_eda.sql` | SQL exploratory analysis in MySQL — fraud rates by type, rule effectiveness, behavioural signals, a self-join, and a window function |
| `PaySim_FraudDetection_Project.ipynb` | Python pipeline — feature engineering, modelling, evaluation, and SHAP interpretation |
| `requirements.txt` | Python dependencies |

## Approach

1. **SQL EDA** (`paysim_eda.sql`) — establish where fraud occurs and which behaviours signal it.
2. **Feature engineering** — turn balance inconsistencies into model-ready features.
3. **Modelling** — Logistic Regression baseline vs XGBoost, selected on AUPRC under severe class imbalance.
4. **Interpretation** — SHAP to confirm the model relies on the engineered behavioural features.

## Key EDA findings (SQL)

- Fraud occurs **only** in `TRANSFER` and `CASH_OUT` — zero in `PAYMENT`, `DEBIT`, `CASH_IN`.
- The built-in rule caught **16 of 8,213** frauds (0.19% recall) — precise but nearly blind.
- **97.6%** of frauds drain the origin account (vs 42.7% of legit transactions).
- **49.6%** of frauds leave the destination balance at zero (vs 0.06% of legit) — the cleanest single signal.
- The TRANSFER -> CASH_OUT mule chain is **not traceable** here (only 3 of 4,097 fraud-transfer destinations ever cash out), so no chaining feature was built.
- Fraud concentrates in the **largest transactions** — the top amount decile holds 45% of all fraud.

## Feature engineering

Two balance-consistency features capture the draining and destination-anomaly patterns found in EDA:

- `errorBalanceOrig = (oldbalanceOrg - amount) - newbalanceOrig`
- `errorBalanceDest = (oldbalanceDest + amount) - newbalanceDest`

Both are ~0 when an account's balance changes consistently with the transaction, and large when it does not — which is exactly the fraud signature.

## Models & results

| Model | AUPRC | ROC-AUC |
|-------|-------|---------|
| Logistic Regression | 0.559 | 0.976 |
| **XGBoost** | **0.994** | **0.998** |

AUPRC is the primary metric because of the 0.13% fraud rate — ROC-AUC is misleadingly high under severe imbalance. At the default 0.5 threshold, XGBoost catches **2,453 of 2,464** held-out frauds (99.6% recall, 92.4% precision) with 201 false alarms across 831K test transactions.

SHAP confirms the model leans on the engineered `errorBalance` features and the raw balance columns — matching the fraud typologies surfaced in EDA.

## How to run

1. Download the dataset from [Kaggle](https://www.kaggle.com/datasets/ealaxi/paysim1).
2. Install dependencies: `pip install -r requirements.txt`
3. Update the CSV path in the notebook (and in `paysim_eda.sql` if running the SQL in MySQL).
4. Run the notebook top to bottom (Kernel -> Restart & Run All).

## Limitations

- PaySim is **synthetic**, so near-perfect scores partly reflect the simulator's clean structure and would not transfer one-to-one to messy real-world data.
- The model is evaluated at a single default threshold; production use would tune the threshold to a business cost trade-off.
- No network/graph features were built, as the money-trail chain is not traceable in this dataset.

## Reference

Lopez-Rojas, E. A., Elmir, A., & Axelsson, S. (2016). *PaySim: A financial mobile money simulator for fraud detection.* The 28th European Modeling and Simulation Symposium (EMSS), Larnaca, Cyprus.
